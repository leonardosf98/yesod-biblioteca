{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Pedido
    ( prazoRetirada
    , expirarPedidos
    , pendencias
    , pedirLivro
    , cancelarPedido
    , cancelarPedidoNoBalcao
    , atenderFila
    , confirmarRetirada
    , diasRenovacao
    , renovarEmprestimo
    ) where

import ClassyPrelude.Yesod
import qualified Data.ByteString as B
import qualified Data.Text as T
import Crypto.Random (getRandomBytes)
import Data.Time (NominalDiffTime, addDays, addUTCTime)
import Database.Persist.Sql (fromSqlKey, updateWhereCount)
import Model
import Model.Tipos
import Regras.Emprestimo (formatarCentavos, hoje, limiteAbertos, prazoDias)
import Regras.Notificacao
import Regras.Reserva (atenderReserva, filaDeReservas)

prazoRetirada :: NominalDiffTime
prazoRetirada = 48 * 60 * 60

expirarPedidos :: MonadIO m => UTCTime -> ReaderT SqlBackend m ()
expirarPedidos agora = do
    vencidos <- selectList [PedidoStatus ==. PedidoAguardando, PedidoLimiteRetirada <=. agora] []
    forM_ vencidos $ \pedido@(Entity pedidoId p) -> do
        livroId <- liberarPedido pedido PedidoExpirado
        titulo <- tituloDoLivro livroId
        notificarSocio (pedidoSocioId p) Aviso
            { avisoTipo = "pedido_expirado"
            , avisoChave = "pedido_expirado:pedido:" <> chaveDe pedidoId
            , avisoTitulo = "Pedido expirado: " <> titulo
            , avisoTexto = "O prazo para retirar o pedido " <> pedidoCodigo p <> " acabou e o exemplar voltou para a estante."
            , avisoLink = Just (linkDoLivro livroId)
            }
        atenderFila livroId agora

liberarPedido :: MonadIO m => Entity Pedido -> StatusPedido -> ReaderT SqlBackend m LivroId
liberarPedido (Entity pedidoId p) status = do
    update pedidoId [PedidoStatus =. status]
    update (pedidoExemplarId p) [ExemplarDisponivel =. True]
    exemplarLivroId <$> getJust (pedidoExemplarId p)

tituloDoLivro :: MonadIO m => LivroId -> ReaderT SqlBackend m Text
tituloDoLivro livroId = maybe "livro" livroTitulo <$> get livroId

linkDoLivro :: LivroId -> Text
linkDoLivro livroId = "/livros/" <> chaveDe livroId

chaveDe :: ToBackendKey SqlBackend r => Key r -> Text
chaveDe = tshow . fromSqlKey

pendencias :: MonadIO m => SocioId -> Day -> ReaderT SqlBackend m [Text]
pendencias socioId dia = do
    multas <- selectList [EmprestimoSocioId ==. socioId, EmprestimoMultaCentavos >. 0, EmprestimoMultaPagaEm ==. Nothing] []
    atrasados <- count [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <. dia]
    let total = sum (map (emprestimoMultaCentavos . entityVal) multas)
    return $ catMaybes
        [ if total > 0 then Just ("Há " <> formatarCentavos total <> " de multa em aberto; pague no balcão para liberar novos pedidos.") else Nothing
        , if atrasados > 0 then Just "Há empréstimo atrasado; devolva no balcão para liberar novos pedidos." else Nothing
        ]

impedimentos :: MonadIO m => SocioId -> LivroId -> Day -> ReaderT SqlBackend m [Text]
impedimentos socioId livroId dia = do
    bloqueios <- pendencias socioId dia
    emprestimos <- selectList [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing] []
    aguardando <- selectList [PedidoSocioId ==. socioId, PedidoStatus ==. PedidoAguardando] []
    exemplaresDoSocio <- selectList
        [ExemplarId <-. (map (emprestimoExemplarId . entityVal) emprestimos ++ map (pedidoExemplarId . entityVal) aguardando)] []
    let emUso = length emprestimos + length aguardando
        jaTem = any ((== livroId) . exemplarLivroId . entityVal) exemplaresDoSocio
    return $ bloqueios
        ++ ["Você já está com " <> tshow emUso <> " livros, o máximo. Devolva um para pedir outro." | emUso >= limiteAbertos]
        ++ ["Você já está com esse livro ou tem um pedido dele aguardando retirada." | jaTem]

exemplaresLivres :: MonadIO m => LivroId -> ReaderT SqlBackend m [ExemplarId]
exemplaresLivres livroId =
    selectKeysList [ExemplarLivroId ==. livroId, ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido] [Asc ExemplarEstado, Asc ExemplarCodigo]

pedirLivro :: MonadIO m => SocioId -> LivroId -> UTCTime -> Day -> ReaderT SqlBackend m (Either Text (Entity Pedido))
pedirLivro socioId livroId agora dia = do
    expirarPedidos agora
    motivos <- impedimentos socioId livroId dia
    fila <- filaDeReservas livroId
    let outroNaFrente = case fila of
            Entity _ r : _ -> reservaSocioId r /= socioId
            [] -> False
    case () of
        _ | m : _ <- motivos -> return (Left m)
          | outroNaFrente -> return (Left "Esse livro tem fila de reservas. Entre na fila para ser avisado.")
          | otherwise -> do
              separado <- exemplaresLivres livroId >>= separarPrimeiro
              case separado of
                  Nothing -> return (Left "Nenhum exemplar disponível agora. Entre na fila para ser avisado.")
                  Just exemplarId -> Right <$> registrarPedido socioId exemplarId agora

registrarPedido :: MonadIO m => SocioId -> ExemplarId -> UTCTime -> ReaderT SqlBackend m (Entity Pedido)
registrarPedido socioId exemplarId agora = do
    codigo <- novoCodigo
    let pedido = Pedido exemplarId socioId codigo agora (addUTCTime prazoRetirada agora) PedidoAguardando Nothing
    pedidoId <- insert pedido
    exemplar <- getJust exemplarId
    titulo <- tituloDoLivro (exemplarLivroId exemplar)
    nome <- maybe "Um sócio" socioNome <$> get socioId
    notificarBibliotecarios Aviso
        { avisoTipo = "pedido_novo"
        , avisoChave = "pedido_novo:pedido:" <> chaveDe pedidoId
        , avisoTitulo = "Novo pedido: " <> titulo
        , avisoTexto = nome <> " pediu " <> titulo <> ". Separe o exemplar " <> exemplarCodigo exemplar <> " (pedido " <> codigo <> ")."
        , avisoLink = Just "/painel/pedidos"
        }
    return (Entity pedidoId pedido)

atenderFila :: MonadIO m => LivroId -> UTCTime -> ReaderT SqlBackend m ()
atenderFila livroId agora = do
    dia <- hoje
    filaDeReservas livroId >>= atender dia
  where
    atender _ [] = return ()
    atender dia (Entity reservaId r : resto) = do
        livres <- exemplaresLivres livroId
        unless (null livres) $ do
            motivos <- impedimentos (reservaSocioId r) livroId dia
            when (null motivos) $ do
                separado <- separarPrimeiro livres
                forM_ separado $ \exemplarId -> do
                    Entity pedidoId p <- registrarPedido (reservaSocioId r) exemplarId agora
                    update reservaId [ReservaStatus =. Atendida]
                    titulo <- tituloDoLivro livroId
                    exemplar <- getJust exemplarId
                    limite <- dataHoraLocal (pedidoLimiteRetirada p)
                    notificarSocio (reservaSocioId r) Aviso
                        { avisoTipo = "fila_disponivel"
                        , avisoChave = "fila_disponivel:pedido:" <> chaveDe pedidoId
                        , avisoTitulo = "Chegou a sua vez: " <> titulo
                        , avisoTexto = "O exemplar " <> exemplarCodigo exemplar <> " está separado para você até " <> limite <> ". Código do pedido: " <> pedidoCodigo p <> "."
                        , avisoLink = Just "/emprestimos"
                        }
            atender dia resto

separarPrimeiro :: MonadIO m => [ExemplarId] -> ReaderT SqlBackend m (Maybe ExemplarId)
separarPrimeiro [] = return Nothing
separarPrimeiro (exemplarId : resto) = do
    reservado <- updateWhereCount [ExemplarId ==. exemplarId, ExemplarDisponivel ==. True] [ExemplarDisponivel =. False]
    if reservado == 1 then return (Just exemplarId) else separarPrimeiro resto

cancelarPedido :: MonadIO m => SocioId -> PedidoId -> ReaderT SqlBackend m (Either Text ())
cancelarPedido socioId pedidoId = do
    encontrado <- get pedidoId
    case encontrado of
        Just p | pedidoSocioId p == socioId && pedidoStatus p == PedidoAguardando -> do
            livroId <- liberarPedido (Entity pedidoId p) PedidoCancelado
            liftIO getCurrentTime >>= atenderFila livroId
            return (Right ())
        _ -> return (Left "Pedido não encontrado ou não pode mais ser cancelado.")

cancelarPedidoNoBalcao :: MonadIO m => PedidoId -> ReaderT SqlBackend m (Either Text ())
cancelarPedidoNoBalcao pedidoId = do
    encontrado <- get pedidoId
    case encontrado of
        Just p | pedidoStatus p == PedidoAguardando -> do
            livroId <- liberarPedido (Entity pedidoId p) PedidoCancelado
            titulo <- tituloDoLivro livroId
            notificarSocio (pedidoSocioId p) Aviso
                { avisoTipo = "pedido_cancelado"
                , avisoChave = "pedido_cancelado:pedido:" <> chaveDe pedidoId
                , avisoTitulo = "Pedido cancelado: " <> titulo
                , avisoTexto = "A biblioteca cancelou o pedido " <> pedidoCodigo p <> ". Se ainda quiser o livro, faça um novo pedido."
                , avisoLink = Just (linkDoLivro livroId)
                }
            liftIO getCurrentTime >>= atenderFila livroId
            return (Right ())
        Just _ -> return (Left "Só pedidos aguardando retirada podem ser cancelados.")
        Nothing -> return (Left "Pedido não encontrado.")

confirmarRetirada :: MonadIO m => PedidoId -> UTCTime -> Day -> ReaderT SqlBackend m (Either Text EmprestimoId)
confirmarRetirada pedidoId agora dia = do
    expirarPedidos agora
    encontrado <- get pedidoId
    case encontrado of
        Nothing -> return (Left "Pedido não encontrado.")
        Just p
            | pedidoStatus p == PedidoExpirado -> return (Left "O prazo de retirada venceu e o exemplar voltou para a estante.")
            | pedidoStatus p /= PedidoAguardando -> return (Left "Esse pedido não está aguardando retirada.")
            | otherwise -> do
                exemplar <- get (pedidoExemplarId p)
                forM_ exemplar $ atenderReserva (pedidoSocioId p) . exemplarLivroId
                emprestimoId <- insert $ Emprestimo (pedidoExemplarId p) (pedidoSocioId p) dia (addDays prazoDias dia) Nothing 0 0 Nothing
                update pedidoId [PedidoStatus =. PedidoRetirado, PedidoEmprestimoId =. Just emprestimoId]
                return (Right emprestimoId)

novoCodigo :: MonadIO m => m Text
novoCodigo = do
    bytes <- liftIO (getRandomBytes 6 :: IO ByteString)
    let alfabeto = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" :: Text
        letras = T.pack [T.index alfabeto (fromIntegral b `mod` T.length alfabeto) | b <- B.unpack bytes]
    return (T.take 2 letras <> "-" <> T.drop 2 letras)

diasRenovacao :: Integer
diasRenovacao = 7

renovarEmprestimo :: MonadIO m => SocioId -> EmprestimoId -> Day -> ReaderT SqlBackend m (Either Text Day)
renovarEmprestimo socioId emprestimoId dia = do
    encontrado <- get emprestimoId
    case encontrado of
        Just e | emprestimoSocioId e == socioId && isNothing (emprestimoDataDevolucao e) -> do
            bloqueios <- pendencias socioId dia
            exemplar <- get (emprestimoExemplarId e)
            fila <- maybe (return []) (filaDeReservas . exemplarLivroId) exemplar
            case () of
                _ | emprestimoRenovacoes e > 0 -> return (Left "Esse empréstimo já foi renovado uma vez. Devolva no balcão até o prazo.")
                  | emprestimoDataPrevista e < dia -> return (Left "O prazo já venceu; devolva no balcão.")
                  | b : _ <- bloqueios -> return (Left b)
                  | not (null fila) -> return (Left "Há fila de reservas para esse livro; não dá para renovar.")
                  | otherwise -> do
                      let novaData = addDays diasRenovacao (emprestimoDataPrevista e)
                      update emprestimoId [EmprestimoDataPrevista =. novaData, EmprestimoRenovacoes +=. 1]
                      return (Right novaData)
        _ -> return (Left "Empréstimo não encontrado.")
