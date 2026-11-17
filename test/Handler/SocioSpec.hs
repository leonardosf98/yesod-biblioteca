{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.SocioSpec (spec) where

import Seed (popular)
import TestImport

enviarSocio :: Route App -> Text -> Text -> Text -> YesodExample App ()
enviarSocio rota nome email telefone = enviarSocioComCep rota nome email telefone ""

enviarSocioComCep :: Route App -> Text -> Text -> Text -> Text -> YesodExample App ()
enviarSocioComCep rota nome email telefone cep = request $ do
    setMethod "POST"
    setUrl rota
    addToken_ ".form-principal"
    byLabelExact "Nome" nome
    byLabelExact "E-mail" email
    byLabelExact "Telefone" telefone
    byLabelExact "CEP" cep
    byLabelExact "Número" ""

socioPorEmail :: Text -> YesodExample App (Entity Socio)
socioPorEmail email = runDB (getBy (UniqueSocioEmail email)) >>= maybe (error "sócio não encontrado") return

spec :: Spec
spec = withApp $ do
    describe "CRUD de sócio" $ do
        it "cadastra sócio normalizando e-mail e telefone" $ do
            entrar
            get SocioNovoR
            enviarSocio SociosR "Carla Dias" "Carla@Example.com" "(11) 98888-7777"
            statusIs 303
            Entity _ socio <- socioPorEmail "carla@example.com"
            assertEq "telefone só com dígitos" (Just "11988887777") (socioTelefone socio)

        it "recusa e-mail inválido e telefone curto" $ do
            entrar
            get SocioNovoR
            enviarSocio SociosR "Carla" "nao-e-email" "1234"
            statusIs 200
            bodyContains "Telefone deve ter DDD + 8 ou 9 dígitos"
            total <- runDB $ count ([] :: [Filter Socio])
            assertEq "nada gravado" 0 total

        it "recusa e-mail repetido" $ do
            entrar
            runDB $ insert_ (Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing)
            get SocioNovoR
            enviarSocio SociosR "Outra Ana" "ANA@example.com" ""
            statusIs 200
            htmlAnyContain ".alert-danger" "Já existe um sócio com esse e-mail."

        it "atualiza o próprio cadastro mantendo o e-mail" $ do
            entrar
            socioId <- runDB $ insert (Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing)
            get (SocioEditarR socioId)
            enviarSocio (SocioR socioId) "Ana Paula" "ana@example.com" ""
            statusIs 303
            socio <- runDB $ getJust socioId
            assertEq "nome novo" "Ana Paula" (socioNome socio)

        it "mantém o endereço sem consultar o ViaCEP quando o CEP não muda" $ do
            entrar
            socioId <- runDB $ insert $ Socio "Ana" "ana@example.com" Nothing (Just "01001000")
                (Just "Praça da Sé") (Just "100") (Just "Sé") (Just "São Paulo") (Just "SP")
            get (SocioEditarR socioId)
            enviarSocioComCep (SocioR socioId) "Ana Paula" "ana@example.com" "" "01001-000"
            statusIs 303
            socio <- runDB $ getJust socioId
            assertEq "logradouro mantido" (Just "Praça da Sé") (socioLogradouro socio)
            assertEq "cidade mantida" (Just "São Paulo") (socioCidade socio)

        it "mostra histórico de empréstimos e reservas" $ do
            entrar
            runDB popular
            Entity socioId _ <- socioPorEmail "ana@example.com"
            get (SocioR socioId)
            statusIs 200
            htmlAnyContain ".emprestimos td" "Dom Casmurro"
            htmlAnyContain ".emprestimos td" "em aberto"
            htmlAnyContain ".reservas li" "Fundação"

        it "não exclui sócio com histórico" $ do
            entrar
            runDB popular
            Entity socioId _ <- socioPorEmail "bruno@example.com"
            get (SocioR socioId)
            request $ do
                setMethod "POST"
                setUrl (SocioExcluirR socioId)
                addToken_ ".form-excluir"
            restante <- runDB $ count [SocioId ==. socioId]
            assertEq "mantido" 1 restante

        it "exclui sócio sem histórico" $ do
            entrar
            socioId <- runDB $ insert (Socio "Novo" "novo@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing)
            get (SocioR socioId)
            request $ do
                setMethod "POST"
                setUrl (SocioExcluirR socioId)
                addToken_ ".form-excluir"
            statusIs 303
            restante <- runDB $ count [SocioId ==. socioId]
            assertEq "removido" 0 restante
