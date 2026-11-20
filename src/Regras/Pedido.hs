{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiWayIf #-}
module Regras.Pedido
    ( expirarPedidos
    , pedirLivro
    , cancelarPedido
    , cancelarPedidoNoBalcao
    , atenderFila
    , confirmarRetirada
    ) where

import ClassyPrelude.Yesod
import Data.Time (addUTCTime)
import Model
import Model.Tipos
import Regras.Comum (dataHoraLocal, hoje, tituloDoLivro)
import Regras.Emprestimo (novoEmprestimo, pendencias, separarExemplar)
import Regras.Notificacao
import Regras.Politica (limiteAbertos, prazoRetirada)
import Regras.Reserva (atenderReserva, filaDeReservas)
import Token (codigoLegivel)

expirarPedidos :: MonadIO m => UTCTime -> ReaderT SqlBackend m ()
expirarPedidos agora = do
    vencidos <- selectList [PedidoStatus ==. PedidoAguardando, PedidoLimiteRetirada <=. agora] []
    forM_ vencidos $ \pedido -> do
        livroId <- liberarPedido pedido PedidoExpirado
        titulo <- tituloDoLivro livroId
        notificarSocio (pedidoSocioId (entityVal pedido)) (avisoPedidoExpirado pedido livroId titulo)
        atenderFila livroId agora

liberarPedido :: MonadIO m => Entity Pedido -> StatusPedido -> ReaderT SqlBackend m LivroId
liberarPedido (Entity pedidoId p) status = do
    update pedidoId [PedidoStatus =. status]
    update (pedidoExemplarId p) [ExemplarDisponivel =. True]
    exemplarLivroId <$> getJust (pedidoExemplarId p)

impedimentos :: MonadIO m => SocioId -> LivroId -> Day -> ReaderT SqlBackend m [Text]
impedimentos socioId livroId dia = do
    bloqueios <- pendencias socioId dia
    emprestimos <- selectList [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing] []
    aguardando <- selectList [PedidoSocioId ==. socioId, PedidoStatus ==. PedidoAguardando] []
    exemplaresDoSocio <- selectList
        [ExemplarId <-. map (emprestimoExemplarId . entityVal) emprestimos ++ map (pedidoExemplarId . entityVal) aguardando] []
    let emUso = length emprestimos + length aguardando
        jaTemEsseLivro = any ((== livroId) . exemplarLivroId . entityVal) exemplaresDoSocio
    return $ bloqueios
        ++ ["Você já está com " <> tshow emUso <> " livros, o máximo. Devolva um para pedir outro." | emUso >= limiteAbertos]
        ++ ["Você já está com esse livro ou tem um pedido dele aguardando retirada." | jaTemEsseLivro]

exemplaresLivres :: MonadIO m => LivroId -> ReaderT SqlBackend m [ExemplarId]
exemplaresLivres livroId = selectKeysList
    [ExemplarLivroId ==. livroId, ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido]
    [Asc ExemplarEstado, Asc ExemplarCodigo]

separarPrimeiroLivre :: MonadIO m => [ExemplarId] -> ReaderT SqlBackend m (Maybe ExemplarId)
separarPrimeiroLivre [] = return Nothing
separarPrimeiroLivre (exemplarId : resto) = do
    separado <- separarExemplar exemplarId
    if separado then return (Just exemplarId) else separarPrimeiroLivre resto

pedirLivro :: MonadIO m => SocioId -> LivroId -> UTCTime -> Day -> ReaderT SqlBackend m (Either Text (Entity Pedido))
pedirLivro socioId livroId agora dia = do
    expirarPedidos agora
    motivos <- impedimentos socioId livroId dia
    fila <- filaDeReservas livroId
    let outroNaFrente = case fila of
            Entity _ primeiro : _ -> reservaSocioId primeiro /= socioId
            [] -> False
    if  | motivo : _ <- motivos -> return (Left motivo)
        | outroNaFrente -> return (Left "Esse livro tem fila de reservas. Entre na fila para ser avisado.")
        | otherwise -> do
            separado <- exemplaresLivres livroId >>= separarPrimeiroLivre
            case separado of
                Nothing -> return (Left "Nenhum exemplar disponível agora. Entre na fila para ser avisado.")
                Just exemplarId -> Right <$> registrarPedido socioId exemplarId agora

registrarPedido :: MonadIO m => SocioId -> ExemplarId -> UTCTime -> ReaderT SqlBackend m (Entity Pedido)
registrarPedido socioId exemplarId agora = do
    codigo <- codigoLegivel 6 2
    let pedido = Pedido
            { pedidoExemplarId = exemplarId
            , pedidoSocioId = socioId
            , pedidoCodigo = codigo
            , pedidoCriadoEm = agora
            , pedidoLimiteRetirada = addUTCTime prazoRetirada agora
            , pedidoStatus = PedidoAguardando
            , pedidoEmprestimoId = Nothing
            }
    pedidoId <- insert pedido
    exemplar <- getJust exemplarId
    titulo <- tituloDoLivro (exemplarLivroId exemplar)
    nome <- maybe "Um sócio" socioNome <$> get socioId
    notificarBibliotecarios (avisoPedidoNovo (Entity pedidoId pedido) nome titulo (exemplarCodigo exemplar))
    return (Entity pedidoId pedido)

-- Percorre a fila em ordem: quem tem pendência é pulado, sem perder o lugar.
atenderFila :: MonadIO m => LivroId -> UTCTime -> ReaderT SqlBackend m ()
atenderFila livroId agora = do
    dia <- hoje
    fila <- filaDeReservas livroId
    forM_ fila $ \(Entity reservaId reserva) -> do
        livres <- exemplaresLivres livroId
        unless (null livres) $ do
            motivos <- impedimentos (reservaSocioId reserva) livroId dia
            when (null motivos) $ do
                separado <- separarPrimeiroLivre livres
                forM_ separado $ \exemplarId -> do
                    pedido <- registrarPedido (reservaSocioId reserva) exemplarId agora
                    update reservaId [ReservaStatus =. Atendida]
                    titulo <- tituloDoLivro livroId
                    exemplar <- getJust exemplarId
                    limite <- dataHoraLocal (pedidoLimiteRetirada (entityVal pedido))
                    notificarSocio (reservaSocioId reserva) (avisoChegouSuaVez pedido titulo (exemplarCodigo exemplar) limite)

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
            let pedido = Entity pedidoId p
            livroId <- liberarPedido pedido PedidoCancelado
            titulo <- tituloDoLivro livroId
            notificarSocio (pedidoSocioId p) (avisoPedidoCancelado pedido livroId titulo)
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
                emprestimoId <- insert (novoEmprestimo (pedidoSocioId p) (pedidoExemplarId p) dia)
                update pedidoId [PedidoStatus =. PedidoRetirado, PedidoEmprestimoId =. Just emprestimoId]
                return (Right emprestimoId)
