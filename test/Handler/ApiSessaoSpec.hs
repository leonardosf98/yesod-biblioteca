{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiSessaoSpec (spec) where

import ApiTeste
import Data.Time (addUTCTime)
import Sessao (hashToken)
import TestImport
import Usuario (salvarBibliotecario)

spec :: Spec
spec = withApp $ describe "API de sessões" $ do
    it "entra com login e senha, sem token CSRF, e usa o token no cabeçalho" $ do
        _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        entrarNaApi "maria" "senha-forte-123"
        statusIs 201
        token <- tokenDaResposta
        comToken (Just token) ApiEuR "GET"
        statusIs 200
        bodyContains "\"papel\":\"bibliotecario\""
        bodyContains "\"login\":\"maria\""

    it "guarda só o hash do token" $ do
        _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        entrarNaApi "maria" "senha-forte-123"
        token <- tokenDaResposta
        sessoes <- runDB $ selectList ([] :: [Filter Sessao]) []
        assertEq "uma sessão" 1 (length sessoes)
        forM_ sessoes $ \(Entity _ s) -> do
            assertNotEq "não guarda o token puro" token (sessaoTokenHash s)
            assertEq "guarda o hash" (hashToken token) (sessaoTokenHash s)

    it "recusa senha errada e usuário inexistente" $ do
        _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        entrarNaApi "maria" "errada-123456"
        statusIs 401
        bodyContains "Login ou senha"
        entrarNaApi "joao" "senha-forte-123"
        statusIs 401

    it "sem token a API responde 401 em JSON" $ do
        comToken Nothing ApiEuR "GET"
        statusIs 401

    it "token desconhecido ou vencido é recusado" $ do
        usuario <- createUser "maria"
        agora <- liftIO getCurrentTime
        runDB $ insert_ $ Sessao (entityKey usuario) (hashToken "vencido") (addUTCTime (-60) agora)
        comToken (Just "vencido") ApiEuR "GET"
        statusIs 401
        comToken (Just "inventado") ApiEuR "GET"
        statusIs 401

    it "sair invalida o token" $ do
        _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        entrarNaApi "maria" "senha-forte-123"
        token <- tokenDaResposta
        comToken (Just token) ApiSessoesR "DELETE"
        statusIs 204
        comToken (Just token) ApiEuR "GET"
        statusIs 401
