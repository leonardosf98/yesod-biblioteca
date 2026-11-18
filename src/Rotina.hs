{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
module Rotina
    ( rodarRotina
    , rodarRotinaEm
    , antecedenciaExpiracao
    ) where

import ClassyPrelude.Yesod
import Data.Time (NominalDiffTime, addDays, addUTCTime)
import Database.Persist.Sql (fromSqlKey)
import Model
import Model.Tipos
import Regras.Emprestimo (calcularMulta, formatarCentavos, hoje)
import Regras.Notificacao
import Regras.Pedido (atenderFila, expirarPedidos)

antecedenciaExpiracao :: NominalDiffTime
antecedenciaExpiracao = 6 * 60 * 60

rodarRotina :: MonadIO m => ReaderT SqlBackend m Int
rodarRotina = do
    agora <- liftIO getCurrentTime
    dia <- hoje
    rodarRotinaEm agora dia

rodarRotinaEm :: MonadIO m => UTCTime -> Day -> ReaderT SqlBackend m Int
rodarRotinaEm agora dia = do
    antes <- count ([] :: [Filter Notificacao])
    expirarPedidos agora
    livrosComFila <- ordNub . map (reservaLivroId . entityVal) <$> selectList [ReservaStatus ==. Ativa] []
    forM_ livrosComFila (`atenderFila` agora)
    avisarPedidosExpirando agora
    avisarDevolucoes dia
    depois <- count ([] :: [Filter Notificacao])
    return (depois - antes)

avisarPedidosExpirando :: MonadIO m => UTCTime -> ReaderT SqlBackend m ()
avisarPedidosExpirando agora = do
    pedidos <- selectList
        [ PedidoStatus ==. PedidoAguardando
        , PedidoLimiteRetirada >. agora
        , PedidoLimiteRetirada <=. addUTCTime antecedenciaExpiracao agora
        ] []
    forM_ pedidos $ \(Entity pedidoId p) -> do
        titulo <- tituloDoExemplar (pedidoExemplarId p)
        limite <- dataHoraLocal (pedidoLimiteRetirada p)
        notificarSocio (pedidoSocioId p) Aviso
            { avisoTipo = "pedido_expirando"
            , avisoChave = "pedido_expirando:pedido:" <> chaveDe pedidoId
            , avisoTitulo = "Retire até " <> limite <> ": " <> titulo
            , avisoTexto = "O pedido " <> pedidoCodigo p <> " expira em menos de 6 horas. Depois disso o exemplar volta para a estante."
            , avisoLink = Just "/emprestimos"
            }

avisarDevolucoes :: MonadIO m => Day -> ReaderT SqlBackend m ()
avisarDevolucoes dia = do
    abertos <- selectList [EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <=. addDays 1 dia] []
    forM_ abertos $ \(Entity emprestimoId e) -> do
        titulo <- tituloDoExemplar (emprestimoExemplarId e)
        let prevista = emprestimoDataPrevista e
            referencia = "emprestimo:" <> chaveDe emprestimoId
        if prevista < dia
            then notificarSocio (emprestimoSocioId e) Aviso
                { avisoTipo = "emprestimo_atrasado"
                , avisoChave = "emprestimo_atrasado:" <> referencia <> ":" <> tshow dia
                , avisoTitulo = "Devolução atrasada: " <> titulo
                , avisoTexto = "O prazo venceu em " <> dataCurta prevista <> ". Multa prevista até hoje: "
                    <> formatarCentavos (calcularMulta prevista dia) <> ". Devolva no balcão."
                , avisoLink = Just "/emprestimos"
                }
            else when (prevista == addDays 1 dia) $ notificarSocio (emprestimoSocioId e) Aviso
                { avisoTipo = "devolucao_vencendo"
                , avisoChave = "devolucao_vencendo:" <> referencia <> ":" <> tshow prevista
                , avisoTitulo = "Devolva amanhã: " <> titulo
                , avisoTexto = "O prazo de devolução vence amanhã, " <> dataCurta prevista <> ". Se não houver fila, dá para renovar uma vez."
                , avisoLink = Just "/emprestimos"
                }

tituloDoExemplar :: MonadIO m => ExemplarId -> ReaderT SqlBackend m Text
tituloDoExemplar exemplarId = do
    exemplar <- get exemplarId
    livro <- maybe (return Nothing) (get . exemplarLivroId) exemplar
    return (maybe "livro" livroTitulo livro)

dataCurta :: Day -> Text
dataCurta = pack . formatTime defaultTimeLocale "%d/%m"

chaveDe :: ToBackendKey SqlBackend r => Key r -> Text
chaveDe = tshow . fromSqlKey
