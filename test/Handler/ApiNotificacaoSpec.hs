{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiNotificacaoSpec (spec) where

import ApiTeste
import Data.Aeson (object, (.=))
import Data.Time (addDays, addUTCTime)
import Regras.Emprestimo (hoje)
import TestImport
import Usuario (salvarBibliotecario)
import Yesod.Auth.HashDB (setPassword)

novoSocio :: Text -> YesodExample App (SocioId, Text)
novoSocio email = do
    socioId <- runDB $ do
        socioId <- insert $ Socio "Sócio" email Nothing Nothing Nothing Nothing Nothing Nothing Nothing
        usuario <- setPassword "senha-socio-1" (User email Nothing PapelSocio (Just socioId))
        insert_ usuario
        return socioId
    entrarNaApi email "senha-socio-1"
    t <- tokenDaResposta
    return (socioId, t)

tokenBibliotecario :: YesodExample App Text
tokenBibliotecario = do
    _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
    entrarNaApi "maria" "senha-forte-123"
    tokenDaResposta

livroComExemplar :: YesodExample App (LivroId, ExemplarId)
livroComExemplar = runDB $ do
    categoria <- insert $ Categoria "Romance" Nothing
    livroId <- insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing Nothing categoria
    exemplarId <- insert $ Exemplar livroId "DC-1" Bom True
    return (livroId, exemplarId)

notificacoesDe :: SocioId -> YesodExample App [Notificacao]
notificacoesDe socioId = runDB $ do
    usuarios <- selectKeysList [UserSocioId ==. Just socioId] []
    map entityVal <$> selectList [NotificacaoUserId <-. usuarios] [Asc NotificacaoId]

tiposDe :: SocioId -> YesodExample App [Text]
tiposDe socioId = map notificacaoTipo <$> notificacoesDe socioId

spec :: Spec
spec = withApp $ describe "Notificações" $ do
    it "pedido novo avisa o bibliotecário, que lê e marca como lida" $ do
        (livroId, _) <- livroComExemplar
        tb <- tokenBibliotecario
        (_, ts) <- novoSocio "ana@example.com"
        enviarJson (Just ts) (ApiLivroPedidosR livroId) (object [])
        statusIs 201
        comToken (Just tb) ApiNotificacoesR "GET"
        statusIs 200
        bodyContains "\"naoLidas\":1"
        bodyContains "\"tipo\":\"pedido_novo\""
        bodyContains "Novo pedido: Dom Casmurro"
        comToken (Just ts) ApiNotificacoesR "GET"
        bodyContains "\"naoLidas\":0"
        Entity notificacaoId _ <- runDB (selectFirst [] []) >>= maybe (error "sem notificação") return
        enviarJson (Just ts) (ApiNotificacaoLeituraR notificacaoId) (object [])
        statusIs 404
        enviarJson (Just tb) (ApiNotificacaoLeituraR notificacaoId) (object [])
        statusIs 204
        comToken (Just tb) ApiNotificacoesR "GET"
        bodyContains "\"naoLidas\":0"

    it "marcar todas como lidas só mexe nas do próprio usuário" $ do
        (livroId, _) <- livroComExemplar
        tb <- tokenBibliotecario
        (_, ts) <- novoSocio "ana@example.com"
        enviarJson (Just ts) (ApiLivroPedidosR livroId) (object [])
        enviarJson (Just ts) ApiNotificacoesLeituraR (object [])
        statusIs 204
        comToken (Just tb) ApiNotificacoesR "GET"
        bodyContains "\"naoLidas\":1"
        enviarJson (Just tb) ApiNotificacoesLeituraR (object [])
        comToken (Just tb) ApiNotificacoesR "GET"
        bodyContains "\"naoLidas\":0"

    it "exige login" $ do
        comToken Nothing ApiNotificacoesR "GET"
        statusIs 401

    it "devolução separa o exemplar para o primeiro da fila e avisa" $ do
        (livroId, exemplarId) <- livroComExemplar
        tb <- tokenBibliotecario
        (leitor, _) <- novoSocio "ana@example.com"
        (naFila, _) <- novoSocio "bia@example.com"
        dia <- hoje
        emprestimoId <- runDB $ do
            update exemplarId [ExemplarDisponivel =. False]
            insert_ $ Reserva livroId naFila dia Ativa
            insert $ Emprestimo exemplarId leitor (addDays (-3) dia) (addDays 11 dia) Nothing 0 0 Nothing
        enviarJson (Just tb) (ApiDevolucaoR emprestimoId) (object [])
        statusIs 200
        pedidos <- runDB $ selectList [PedidoSocioId ==. naFila, PedidoStatus ==. PedidoAguardando] []
        assertEq "pedido separado para quem estava na fila" 1 (length pedidos)
        disponivel <- runDB $ exemplarDisponivel <$> getJust exemplarId
        assertEq "exemplar fica separado" False disponivel
        reservas <- runDB $ count [ReservaSocioId ==. naFila, ReservaStatus ==. Atendida]
        assertEq "reserva atendida" 1 reservas
        tipos <- tiposDe naFila
        assertEq "aviso de vez na fila" ["fila_disponivel"] tipos

    it "fila pula quem está bloqueado" $ do
        (livroId, exemplarId) <- livroComExemplar
        (bloqueado, _) <- novoSocio "ana@example.com"
        (liberado, _) <- novoSocio "bia@example.com"
        tb <- tokenBibliotecario
        dia <- hoje
        runDB $ do
            categoria <- insert $ Categoria "Outros" Nothing
            outro <- insert $ Livro "Antigo" Nothing Nothing Nothing Nothing Nothing categoria
            e <- insert $ Exemplar outro "AN-1" Bom False
            insert_ $ Emprestimo e bloqueado (addDays (-30) dia) (addDays (-2) dia) Nothing 0 0 Nothing
            update exemplarId [ExemplarDisponivel =. False]
            insert_ $ Reserva livroId bloqueado dia Ativa
            insert_ $ Reserva livroId liberado dia Ativa
        enviarJson (Just tb) (ApiLivroExemplaresR livroId) (object ["estado" .= ("bom" :: Text)])
        statusIs 201
        pedidos <- runDB $ map (pedidoSocioId . entityVal) <$> selectList [PedidoStatus ==. PedidoAguardando] []
        assertEq "o exemplar novo vai para o segundo da fila" [liberado] pedidos

    it "bibliotecário cancela o pedido e o sócio é avisado" $ do
        (livroId, exemplarId) <- livroComExemplar
        tb <- tokenBibliotecario
        (socioId, ts) <- novoSocio "ana@example.com"
        enviarJson (Just ts) (ApiLivroPedidosR livroId) (object [])
        pedidoId <- idDaResposta
        comToken (Just ts) (ApiPedidoR pedidoId) "DELETE"
        statusIs 403
        comToken (Just tb) (ApiPedidoR pedidoId) "DELETE"
        statusIs 204
        status <- runDB $ pedidoStatus <$> getJust pedidoId
        assertEq "pedido cancelado" PedidoCancelado status
        disponivel <- runDB $ exemplarDisponivel <$> getJust exemplarId
        assertEq "exemplar volta para a estante" True disponivel
        tipos <- tiposDe socioId
        assertEq "aviso de cancelamento" ["pedido_cancelado"] tipos
        comToken (Just tb) (ApiPedidoR pedidoId) "DELETE"
        statusIs 409

    it "pedido vencido avisa o sócio e passa o exemplar para a fila" $ do
        (livroId, _) <- livroComExemplar
        (primeiro, t1) <- novoSocio "ana@example.com"
        (segundo, _) <- novoSocio "bia@example.com"
        enviarJson (Just t1) (ApiLivroPedidosR livroId) (object [])
        pedidoId <- idDaResposta
        dia <- hoje
        agora <- liftIO getCurrentTime
        runDB $ do
            insert_ $ Reserva livroId segundo dia Ativa
            update pedidoId [PedidoLimiteRetirada =. addUTCTime (-1) agora]
        comToken Nothing (ApiLivroR livroId) "GET"
        tipos <- tiposDe primeiro
        assertEq "aviso de expiração" ["pedido_expirado"] tipos
        doSegundo <- runDB $ count [PedidoSocioId ==. segundo, PedidoStatus ==. PedidoAguardando]
        assertEq "segundo recebe o exemplar" 1 doSegundo
