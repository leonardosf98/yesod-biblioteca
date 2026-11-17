{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiBalcaoSpec (spec) where

import ApiTeste
import Data.Aeson (object, (.=))
import Data.Time (addDays, addUTCTime)
import Regras.Emprestimo (hoje)
import TestImport
import Usuario (salvarBibliotecario)

data Balcao = Balcao
    { ana :: SocioId
    , bruno :: SocioId
    , livre :: ExemplarId
    , emprestado :: ExemplarId
    , atrasado :: EmprestimoId
    , token :: Text
    }

montar :: YesodExample App Balcao
montar = do
    dia <- hoje
    agora <- liftIO getCurrentTime
    (a, b, e1, e2, atr) <- runDB $ do
        categoria <- insert $ Categoria "Romance" Nothing
        l1 <- insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing Nothing categoria
        l2 <- insert $ Livro "Vidas Secas" Nothing Nothing Nothing Nothing Nothing categoria
        l3 <- insert $ Livro "Fundação" Nothing Nothing Nothing Nothing Nothing categoria
        e1 <- insert $ Exemplar l1 "DC-1" Bom True
        e2 <- insert $ Exemplar l2 "VS-1" Bom False
        e3 <- insert $ Exemplar l3 "FU-1" Bom False
        e4 <- insert $ Exemplar l1 "DC-2" Bom False
        a <- insert $ Socio "Ana Souza" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
        b <- insert $ Socio "Bruno Lima" "bruno@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
        atr <- insert $ Emprestimo e2 a (addDays (-20) dia) (addDays (-3) dia) Nothing 0 0 Nothing
        insert_ $ Emprestimo e3 b (addDays (-14) dia) dia Nothing 0 0 Nothing
        insert_ $ Pedido e4 b "AB-CDEF" agora (addUTCTime 3600 agora) PedidoAguardando Nothing
        return (a, b, e1, e2, atr)
    _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
    entrarNaApi "maria" "senha-forte-123"
    Balcao a b e1 e2 atr <$> tokenDaResposta

spec :: Spec
spec = withApp $ describe "API do balcão" $ do
    it "painel traz números, pedidos, atrasados e devoluções de hoje" $ do
        c <- montar
        comToken (Just (token c)) ApiPainelR "GET"
        statusIs 200
        bodyContains "\"abertos\":2"
        bodyContains "\"atrasados\":1"
        bodyContains "\"multaAtrasadosCentavos\":300"
        bodyContains "\"devolucoesHoje\":1"
        bodyContains "\"pedidos\":1"
        bodyContains "\"codigo\":\"AB-CDEF\""
        bodyContains "\"nome\":\"Ana Souza\""

    it "sócio e visitante não veem o painel" $ do
        _ <- montar
        comToken Nothing ApiPainelR "GET"
        statusIs 401

    it "acha o exemplar pelo código, com o empréstimo em aberto" $ do
        c <- montar
        comToken (Just (token c)) (ApiExemplarCodigoR "vs-1") "GET"
        statusIs 200
        bodyContains "\"titulo\":\"Vidas Secas\""
        bodyContains "\"nome\":\"Ana Souza\""
        bodyContains "\"multaCentavos\":300"
        comToken (Just (token c)) (ApiExemplarCodigoR "XX-9") "GET"
        statusIs 404

    it "empresta no balcão, mas não para quem tem pendência" $ do
        c <- montar
        enviarJson (Just (token c)) ApiEmprestimosR (object ["socioId" .= ana c, "exemplarId" .= livre c])
        statusIs 409
        bodyContains "atrasado"
        enviarJson (Just (token c)) ApiEmprestimosR (object ["socioId" .= bruno c, "exemplarId" .= emprestado c])
        statusIs 409
        enviarJson (Just (token c)) ApiEmprestimosR (object ["socioId" .= bruno c, "exemplarId" .= livre c])
        statusIs 201
        bodyContains "\"dataPrevista\""

    it "registra a devolução com multa uma vez só" $ do
        c <- montar
        enviarJson (Just (token c)) (ApiDevolucaoR (atrasado c)) (object [])
        statusIs 200
        bodyContains "\"multaCentavos\":300"
        disponivel <- runDB $ exemplarDisponivel <$> getJust (emprestado c)
        assertEq "volta para a estante" True disponivel
        enviarJson (Just (token c)) (ApiDevolucaoR (atrasado c)) (object [])
        statusIs 409

    it "busca sócios por nome ou e-mail com a situação de cada um" $ do
        c <- montar
        request $ do
            setMethod "GET"
            setUrl ApiSociosR
            addGetParam "busca" "brun"
            addRequestHeader ("Accept", "application/json")
            addRequestHeader ("Authorization", "Bearer " <> encodeUtf8 (token c))
        statusIs 200
        bodyContains "\"nome\":\"Bruno Lima\""
        bodyNotContains "Ana Souza"
        bodyContains "\"emUso\":2"
        bodyContains "\"contaAtiva\":false"
