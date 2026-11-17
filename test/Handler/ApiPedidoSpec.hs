{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiPedidoSpec (spec) where

import ApiTeste
import Data.Aeson (object)
import Data.Time (addDays, addUTCTime)
import Regras.Emprestimo (hoje)
import TestImport
import Usuario (salvarBibliotecario)
import Yesod.Auth.HashDB (setPassword)

data Cenario = Cenario
    { livro :: LivroId
    , outroLivro :: LivroId
    , exemplar :: ExemplarId
    , socio :: SocioId
    , token :: Text
    }

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

cenario :: YesodExample App Cenario
cenario = do
    (livroId, outroId, exemplarId) <- runDB $ do
        categoria <- insert $ Categoria "Romance" Nothing
        l1 <- insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing Nothing categoria
        l2 <- insert $ Livro "Vidas Secas" Nothing Nothing Nothing Nothing Nothing categoria
        e1 <- insert $ Exemplar l1 "DC-1" Bom True
        insert_ $ Exemplar l2 "VS-1" Bom True
        return (l1, l2, e1)
    (socioId, t) <- novoSocio "ana@example.com"
    return (Cenario livroId outroId exemplarId socioId t)

pedir :: Text -> LivroId -> YesodExample App ()
pedir t livroId = enviarJson (Just t) (ApiLivroPedidosR livroId) (object [])

pedidoUnico :: YesodExample App (Entity Pedido)
pedidoUnico = runDB (selectFirst [] [Desc PedidoId]) >>= maybe (error "sem pedido") return

tokenBibliotecario :: YesodExample App Text
tokenBibliotecario = do
    _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
    entrarNaApi "maria" "senha-forte-123"
    tokenDaResposta

spec :: Spec
spec = withApp $ describe "Pedido de empréstimo pelo sócio" $ do
    it "separa um exemplar, devolve o código e tira o livro da disponibilidade" $ do
        c <- cenario
        pedir (token c) (livro c)
        statusIs 201
        bodyContains "\"codigo\""
        disponivel <- runDB $ exemplarDisponivel <$> getJust (exemplar c)
        assertEq "exemplar separado" False disponivel
        comToken Nothing (ApiLivroR (livro c)) "GET"
        bodyContains "\"disponiveis\":0"

    it "só sócio pede" $ do
        c <- cenario
        pedir "" (livro c)
        statusIs 401
        t <- tokenBibliotecario
        pedir t (livro c)
        statusIs 403

    it "recusa sem exemplar, livro repetido e acima do limite" $ do
        c <- cenario
        pedir (token c) (livro c)
        statusIs 201
        pedir (token c) (livro c)
        statusIs 409
        bodyContains "já está com esse livro"
        runDB $ do
            categoria <- insert $ Categoria "Outros" Nothing
            forM_ ["A", "B"] $ \titulo -> do
                l <- insert $ Livro titulo Nothing Nothing Nothing Nothing Nothing categoria
                e <- insert $ Exemplar l ("X-" <> titulo) Bom False
                insert_ $ Emprestimo e (socio c) (fromGregorian 2026 11 10) (fromGregorian 2099 1 1) Nothing 0 0 Nothing
        pedir (token c) (outroLivro c)
        statusIs 409
        bodyContains "o máximo"
        (_, t2) <- novoSocio "bia@example.com"
        pedir t2 (livro c)
        statusIs 409
        bodyContains "Nenhum exemplar disponível"

    it "multa não paga ou atraso bloqueiam o pedido" $ do
        c <- cenario
        dia <- hoje
        emprestimoId <- runDB $ do
            categoria <- insert $ Categoria "Outros" Nothing
            l <- insert $ Livro "Antigo" Nothing Nothing Nothing Nothing Nothing categoria
            e <- insert $ Exemplar l "AN-1" Bom True
            insert $ Emprestimo e (socio c) (addDays (-30) dia) (addDays (-16) dia) (Just (addDays (-14) dia)) 200 0 Nothing
        pedir (token c) (livro c)
        statusIs 409
        bodyContains "R$ 2,00 de multa"
        runDB $ update emprestimoId [EmprestimoMultaPagaEm =. Just dia]
        runDB $ update emprestimoId [EmprestimoDataDevolucao =. Nothing]
        pedir (token c) (livro c)
        statusIs 409
        bodyContains "atrasado"

    it "respeita a fila de reservas" $ do
        c <- cenario
        (outro, _) <- novoSocio "bia@example.com"
        dia <- hoje
        runDB $ insert_ $ Reserva (livro c) outro dia Ativa
        pedir (token c) (livro c)
        statusIs 409
        bodyContains "fila"
        runDB $ updateWhere [ReservaSocioId ==. outro] [ReservaStatus =. Cancelada]
        runDB $ insert_ $ Reserva (livro c) (socio c) dia Ativa
        pedir (token c) (livro c)
        statusIs 201

    it "pedido vencido expira e devolve o exemplar à estante" $ do
        c <- cenario
        pedir (token c) (livro c)
        Entity pedidoId _ <- pedidoUnico
        agora <- liftIO getCurrentTime
        runDB $ update pedidoId [PedidoLimiteRetirada =. addUTCTime (-1) agora]
        comToken Nothing (ApiLivroR (livro c)) "GET"
        bodyContains "\"disponiveis\":1"
        comToken (Just (token c)) ApiEuEmprestimosR "GET"
        statusIs 200
        bodyContains "\"pedidos\":[]"
        status <- runDB $ pedidoStatus <$> getJust pedidoId
        assertEq "expirado" PedidoExpirado status
        disponivel <- runDB $ exemplarDisponivel <$> getJust (exemplar c)
        assertEq "de volta" True disponivel
        t <- tokenBibliotecario
        enviarJson (Just t) (ApiPedidoRetiradaR pedidoId) (object [])
        statusIs 409

    it "sócio cancela o próprio pedido, mas não o de outro" $ do
        c <- cenario
        pedir (token c) (livro c)
        Entity pedidoId _ <- pedidoUnico
        (_, t2) <- novoSocio "bia@example.com"
        comToken (Just t2) (ApiEuPedidoR pedidoId) "DELETE"
        statusIs 404
        comToken (Just (token c)) (ApiEuPedidoR pedidoId) "DELETE"
        statusIs 204
        disponivel <- runDB $ exemplarDisponivel <$> getJust (exemplar c)
        assertEq "liberado" True disponivel

    it "bibliotecário confirma a retirada e o empréstimo começa com 14 dias" $ do
        c <- cenario
        pedir (token c) (livro c)
        Entity pedidoId _ <- pedidoUnico
        t <- tokenBibliotecario
        enviarJson (Just t) (ApiPedidoRetiradaR pedidoId) (object [])
        statusIs 201
        dia <- hoje
        emprestimos <- runDB $ selectList [EmprestimoSocioId ==. socio c] []
        assertEq "prazo" [addDays 14 dia] (map (emprestimoDataPrevista . entityVal) emprestimos)
        enviarJson (Just t) (ApiPedidoRetiradaR pedidoId) (object [])
        statusIs 409
        enviarJson (Just (token c)) (ApiPedidoRetiradaR pedidoId) (object [])
        statusIs 403

    it "meus empréstimos mostra empréstimos, pedidos, reservas e o que está em uso" $ do
        c <- cenario
        dia <- hoje
        pedir (token c) (livro c)
        runDB $ insert_ $ Reserva (outroLivro c) (socio c) dia Ativa
        comToken (Just (token c)) ApiEuEmprestimosR "GET"
        statusIs 200
        bodyContains "\"titulo\":\"Dom Casmurro\""
        bodyContains "\"posicao\":1"
        bodyContains "\"emUso\":1"
        bodyContains "\"pendencias\":[]"
