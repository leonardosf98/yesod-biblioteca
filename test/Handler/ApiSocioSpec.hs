{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiSocioSpec (spec) where

import ApiTeste
import Data.Aeson (Value, encode, object, (.=))
import TestImport
import Usuario (salvarBibliotecario)
import Yesod.Auth.HashDB (setPassword)

bibliotecario :: YesodExample App Text
bibliotecario = do
    _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
    entrarNaApi "maria" "senha-forte-123"
    tokenDaResposta

enviar :: ByteString -> Text -> Route App -> Value -> YesodExample App ()
enviar metodo t rota corpo = request $ do
    setMethod metodo
    setUrl rota
    addRequestHeader ("Accept", "application/json")
    addRequestHeader ("Content-Type", "application/json")
    addRequestHeader ("Authorization", "Bearer " <> encodeUtf8 t)
    setRequestBody (encode corpo)

spec :: Spec
spec = withApp $ describe "API de sócios" $ do
    it "cadastra com e-mail em minúsculas e telefone só com dígitos" $ do
        t <- bibliotecario
        enviarJson (Just t) ApiSociosR $ object
            ["nome" .= ("Ana Souza" :: Text), "email" .= ("Ana@Example.com" :: Text), "telefone" .= ("(11) 98888-7777" :: Text)]
        statusIs 201
        socioId <- idDaResposta
        socio <- runDB $ getJust socioId
        assertEq "email" "ana@example.com" (socioEmail socio)
        assertEq "telefone" (Just "11988887777") (socioTelefone socio)
        comToken (Just t) (ApiSocioR socioId) "GET"
        statusIs 200
        bodyContains "\"contaAtiva\":false"

    it "valida nome, e-mail, telefone e CEP" $ do
        t <- bibliotecario
        enviarJson (Just t) ApiSociosR $ object
            ["nome" .= ("" :: Text), "email" .= ("sem-arroba" :: Text), "telefone" .= ("123" :: Text), "cep" .= ("1234" :: Text)]
        statusIs 400
        forM_ ["nome", "email", "telefone", "cep"] $ \c -> bodyContains ("\"" <> c <> "\":")

    it "recusa e-mail repetido" $ do
        t <- bibliotecario
        _ <- runDB $ insert $ Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
        enviarJson (Just t) ApiSociosR $ object ["nome" .= ("Outra Ana" :: Text), "email" .= ("ANA@example.com" :: Text)]
        statusIs 409

    it "trocar o e-mail troca o login do app e mantém o endereço do mesmo CEP" $ do
        t <- bibliotecario
        socioId <- runDB $ do
            socioId <- insert $ Socio "Ana" "ana@example.com" Nothing (Just "01001000") (Just "Praça da Sé") (Just "100") (Just "Sé") (Just "São Paulo") (Just "SP")
            usuario <- setPassword "senha-socio-1" (User "ana@example.com" Nothing PapelSocio (Just socioId))
            insert_ usuario
            return socioId
        enviar "PUT" t (ApiSocioR socioId) $ object
            ["nome" .= ("Ana Souza" :: Text), "email" .= ("ana.souza@example.com" :: Text), "cep" .= ("01001-000" :: Text), "numero" .= ("200" :: Text)]
        statusIs 200
        socio <- runDB $ getJust socioId
        assertEq "cidade mantida" (Just "São Paulo") (socioCidade socio)
        entrarNaApi "ana.souza@example.com" "senha-socio-1"
        statusIs 201

    it "só exclui sócio sem histórico e apaga a conta do app junto" $ do
        t <- bibliotecario
        (comHistorico, semHistorico) <- runDB $ do
            categoria <- insert $ Categoria "Romance" Nothing
            livro <- insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing Nothing categoria
            a <- insert $ Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
            b <- insert $ Socio "Bia" "bia@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
            insert_ $ Reserva livro a (fromGregorian 2026 11 1) Cancelada
            usuario <- setPassword "senha-socio-1" (User "bia@example.com" Nothing PapelSocio (Just b))
            insert_ usuario
            return (a, b)
        comToken (Just t) (ApiSocioR comHistorico) "DELETE"
        statusIs 409
        comToken (Just t) (ApiSocioR semHistorico) "DELETE"
        statusIs 204
        conta <- runDB $ getBy (UniqueUser "bia@example.com")
        assertEq "conta apagada" True (isNothing conta)
