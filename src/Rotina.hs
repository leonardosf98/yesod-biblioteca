{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE MultiWayIf #-}
module Rotina
    ( rodarRotina
    , rodarRotinaEm
    ) where

import ClassyPrelude.Yesod
import Data.Time (addDays, addUTCTime)
import Model
import Model.Tipos
import Regras.Comum (dataHoraLocal, hoje, tituloDoExemplar)
import Regras.Emprestimo (calcularMulta)
import Regras.Notificacao
import Regras.Pedido (atenderFila, expirarPedidos)
import Regras.Politica (antecedenciaExpiracao)

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
    forM_ pedidos $ \pedido@(Entity _ p) -> do
        titulo <- tituloDoExemplar (pedidoExemplarId p)
        limite <- dataHoraLocal (pedidoLimiteRetirada p)
        notificarSocio (pedidoSocioId p) (avisoPedidoExpirando pedido titulo limite)

avisarDevolucoes :: MonadIO m => Day -> ReaderT SqlBackend m ()
avisarDevolucoes dia = do
    abertos <- selectList [EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <=. addDays 1 dia] []
    forM_ abertos $ \emprestimo@(Entity _ e) -> do
        titulo <- tituloDoExemplar (emprestimoExemplarId e)
        let prevista = emprestimoDataPrevista e
            avisar = notificarSocio (emprestimoSocioId e)
        if  | prevista < dia -> avisar (avisoEmprestimoAtrasado emprestimo dia titulo (calcularMulta prevista dia))
            | prevista == addDays 1 dia -> avisar (avisoDevolucaoAmanha emprestimo titulo)
            | otherwise -> return ()
