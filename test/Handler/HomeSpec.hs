{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.HomeSpec (spec) where

import ApiTeste
import Network.Wai.Test (simpleHeaders)
import TestImport

spec :: Spec
spec = withApp $ describe "Raiz e erros da API" $ do
    it "a raiz responde JSON apontando para a documentação" $ do
        comToken Nothing HomeR "GET"
        statusIs 200
        bodyContains "\"documentacao\""

    it "erros saem em JSON com a mensagem" $ do
        get ("/api/nao-existe" :: Text)
        statusIs 404
        bodyContains "\"erro\":\"Recurso não encontrado.\""
        comToken Nothing PainelR "GET"
        statusIs 401
        bodyContains "\"erro\""

    it "não cria cookie de sessão" $ do
        comToken Nothing LivrosR "GET"
        statusIs 200
        resposta <- getResponse
        let cabecalhos = maybe [] simpleHeaders resposta
        assertEq "sem Set-Cookie" [] [v | (k, v) <- cabecalhos, k == "Set-Cookie"]
