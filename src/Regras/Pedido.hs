{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Pedido
    ( prazoRetirada
    , expirarPedidos
    , pendencias
    , pedirLivro
    , cancelarPedido
    , confirmarRetirada
    ) where

import ClassyPrelude.Yesod
import qualified Data.ByteString as B
import qualified Data.Text as T
import Crypto.Random (getRandomBytes)
import Data.Time (NominalDiffTime, addDays, addUTCTime)
import Database.Persist.Sql (updateWhereCount)
import Model
import Model.Tipos
import Regras.Emprestimo (formatarCentavos, limiteAbertos, prazoDias)
import Regras.Reserva (atenderReserva, filaDeReservas)

prazoRetirada :: NominalDiffTime
prazoRetirada = 48 * 60 * 60

expirarPedidos :: MonadIO m => UTCTime -> ReaderT SqlBackend m ()
expirarPedidos agora = do
    vencidos <- selectList [PedidoStatus ==. PedidoAguardando, PedidoLimiteRetirada <=. agora] []
    forM_ vencidos $ \(Entity pedidoId p) -> do
        update pedidoId [PedidoStatus =. PedidoExpirado]
        update (pedidoExemplarId p) [ExemplarDisponivel =. True]

pendencias :: MonadIO m => SocioId -> Day -> ReaderT SqlBackend m [Text]
pendencias socioId dia = do
    multas <- selectList [EmprestimoSocioId ==. socioId, EmprestimoMultaCentavos >. 0, EmprestimoMultaPagaEm ==. Nothing] []
    atrasados <- count [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <. dia]
    let total = sum (map (emprestimoMultaCentavos . entityVal) multas)
    return $ catMaybes
        [ if total > 0 then Just ("Há " <> formatarCentavos total <> " de multa em aberto; pague no balcão para liberar novos pedidos.") else Nothing
        , if atrasados > 0 then Just "Há empréstimo atrasado; devolva no balcão para liberar novos pedidos." else Nothing
        ]

pedirLivro :: MonadIO m => SocioId -> LivroId -> UTCTime -> Day -> ReaderT SqlBackend m (Either Text (Entity Pedido))
pedirLivro socioId livroId agora dia = do
    expirarPedidos agora
    bloqueios <- pendencias socioId dia
    emprestimos <- selectList [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing] []
    aguardando <- selectList [PedidoSocioId ==. socioId, PedidoStatus ==. PedidoAguardando] []
    exemplaresDoSocio <- selectList
        [ExemplarId <-. (map (emprestimoExemplarId . entityVal) emprestimos ++ map (pedidoExemplarId . entityVal) aguardando)] []
    fila <- filaDeReservas livroId
    let emUso = length emprestimos + length aguardando
        jaTem = any ((== livroId) . exemplarLivroId . entityVal) exemplaresDoSocio
        outroNaFrente = case fila of
            Entity _ r : _ -> reservaSocioId r /= socioId
            [] -> False
    case () of
        _ | b : _ <- bloqueios -> return (Left b)
          | emUso >= limiteAbertos -> return (Left ("Você já está com " <> tshow emUso <> " livros, o máximo. Devolva um para pedir outro."))
          | jaTem -> return (Left "Você já está com esse livro ou tem um pedido dele aguardando retirada.")
          | outroNaFrente -> return (Left "Esse livro tem fila de reservas. Entre na fila para ser avisado.")
          | otherwise -> do
              livres <- selectKeysList [ExemplarLivroId ==. livroId, ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido] [Asc ExemplarEstado, Asc ExemplarCodigo]
              separado <- separarPrimeiro livres
              case separado of
                  Nothing -> return (Left "Nenhum exemplar disponível agora. Entre na fila para ser avisado.")
                  Just exemplarId -> do
                      codigo <- novoCodigo
                      let pedido = Pedido exemplarId socioId codigo agora (addUTCTime prazoRetirada agora) PedidoAguardando Nothing
                      pedidoId <- insert pedido
                      return (Right (Entity pedidoId pedido))

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
            update pedidoId [PedidoStatus =. PedidoCancelado]
            update (pedidoExemplarId p) [ExemplarDisponivel =. True]
            return (Right ())
        _ -> return (Left "Pedido não encontrado ou não pode mais ser cancelado.")

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
