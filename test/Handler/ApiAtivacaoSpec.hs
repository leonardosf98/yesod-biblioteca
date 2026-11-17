{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiAtivacaoSpec (spec) where

import ApiTeste
import Data.Aeson (Value, object, (.=))
import Data.Time (addUTCTime)
import Regras.Ativacao (maximoTentativas, normalizarCodigo)
import Sessao (hashToken)
import TestImport
import Usuario (salvarBibliotecario)

novoSocio :: Text -> YesodExample App SocioId
novoSocio email = runDB $ insert $ Socio "Ana Souza" email Nothing Nothing Nothing Nothing Nothing Nothing Nothing

tokenBibliotecario :: YesodExample App Text
tokenBibliotecario = do
    _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
    entrarNaApi "maria" "senha-forte-123"
    tokenDaResposta

gerarCodigo :: SocioId -> YesodExample App Text
gerarCodigo socioId = do
    token <- tokenBibliotecario
    enviarJson (Just token) (ApiSocioCodigoR socioId) (object [])
    statusIs 201
    campoDaResposta "codigo" >>= maybe (liftIO (expectationFailure "sem código") >> return "") return

ativar :: Text -> Text -> Text -> YesodExample App ()
ativar email codigo senha = enviarJson Nothing ApiAtivacaoR $
    object ["email" .= email, "codigo" .= codigo, "senha" .= senha]

spec :: Spec
spec = withApp $ describe "Ativação da conta do sócio" $ do
    it "bibliotecário gera o código e o banco guarda só o hash" $ do
        socioId <- novoSocio "ana@example.com"
        codigo <- gerarCodigo socioId
        assertEq "formato XXXX-XXXX" 9 (length codigo)
        registros <- runDB $ selectList [CodigoAtivacaoSocioId ==. socioId] []
        assertEq "guarda o hash" [hashToken (normalizarCodigo codigo)] (map (codigoAtivacaoHash . entityVal) registros)

    it "sócio ativa com o código, entra na API e o código não vale de novo" $ do
        socioId <- novoSocio "ana@example.com"
        codigo <- gerarCodigo socioId
        ativar "Ana@Example.com" (toLower codigo) "minha-senha-1"
        statusIs 200
        entrarNaApi "ana@example.com" "minha-senha-1"
        statusIs 201
        token <- tokenDaResposta
        comToken (Just token) ApiEuR "GET"
        bodyContains "\"papel\":\"socio\""
        usuario <- runDB $ getBy (UniqueUser "ana@example.com")
        assertEq "liga o usuário ao sócio" (Just (Just socioId)) (userSocioId . entityVal <$> usuario)
        ativar "ana@example.com" codigo "outra-senha-2"
        statusIs 400

    it "recusa código errado, de outro e-mail ou vencido" $ do
        socioId <- novoSocio "ana@example.com"
        _ <- novoSocio "bia@example.com"
        codigo <- gerarCodigo socioId
        ativar "ana@example.com" "ZZZZ-ZZZZ" "minha-senha-1"
        statusIs 400
        bodyContains "inválido ou vencido"
        ativar "bia@example.com" codigo "minha-senha-1"
        statusIs 400
        agora <- liftIO getCurrentTime
        runDB $ updateWhere [CodigoAtivacaoSocioId ==. socioId] [CodigoAtivacaoExpiraEm =. addUTCTime (-1) agora]
        ativar "ana@example.com" codigo "minha-senha-1"
        statusIs 400

    it "bloqueia o código depois de tentativas demais" $ do
        socioId <- novoSocio "ana@example.com"
        codigo <- gerarCodigo socioId
        forM_ [1 .. maximoTentativas] $ \_ -> ativar "ana@example.com" "ZZZZ-ZZZZ" "minha-senha-1"
        ativar "ana@example.com" codigo "minha-senha-1"
        statusIs 400

    it "recusa senha curta sem gastar o código" $ do
        socioId <- novoSocio "ana@example.com"
        codigo <- gerarCodigo socioId
        ativar "ana@example.com" codigo "curta"
        statusIs 400
        bodyContains "8 caracteres"
        ativar "ana@example.com" codigo "minha-senha-1"
        statusIs 200

    it "código novo invalida o anterior" $ do
        socioId <- novoSocio "ana@example.com"
        antigo <- gerarCodigo socioId
        _ <- gerarCodigo socioId
        ativar "ana@example.com" antigo "minha-senha-1"
        statusIs 400

    it "redefinir a senha encerra as sessões abertas" $ do
        socioId <- novoSocio "ana@example.com"
        gerarCodigo socioId >>= \c -> ativar "ana@example.com" c "minha-senha-1"
        entrarNaApi "ana@example.com" "minha-senha-1"
        tokenAntigo <- tokenDaResposta
        gerarCodigo socioId >>= \c -> ativar "ana@example.com" c "senha-nova-22"
        statusIs 200
        comToken (Just tokenAntigo) ApiEuR "GET"
        statusIs 401

    it "sócio não gera código" $ do
        socioId <- novoSocio "ana@example.com"
        gerarCodigo socioId >>= \c -> ativar "ana@example.com" c "minha-senha-1"
        entrarNaApi "ana@example.com" "minha-senha-1"
        token <- tokenDaResposta
        enviarJson (Just token) (ApiSocioCodigoR socioId) (object [] :: Value)
        statusIs 403

    it "bibliotecário gera o código pela página do sócio" $ do
        entrar
        socioId <- novoSocio "ana@example.com"
        get (SocioR socioId)
        request $ do
            setMethod "POST"
            setUrl (SocioCodigoR socioId)
            addToken_ ".form-codigo"
        statusIs 303
        _ <- followRedirect
        htmlAnyContain ".alert" "Código de ativação"

    it "não transforma conta de bibliotecário em conta de sócio" $ do
        _ <- runDB $ salvarBibliotecario "ana@example.com" "senha-da-ana-1"
        socioId <- novoSocio "ana@example.com"
        gerarCodigo socioId >>= \c -> ativar "ana@example.com" c "minha-senha-1"
        statusIs 400
        usuario <- runDB $ getBy (UniqueUser "ana@example.com")
        assertEq "continua bibliotecário" (Just PapelBibliotecario) (userPapel . entityVal <$> usuario)
