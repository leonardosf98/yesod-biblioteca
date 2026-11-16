{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.AutorSpec (spec) where

import Seed (popular)
import TestImport

enviarAutor :: Route App -> Text -> Text -> YesodExample App ()
enviarAutor rota nome nacionalidade = request $ do
    setMethod "POST"
    setUrl rota
    addToken
    byLabelExact "Nome" nome
    byLabelExact "Nacionalidade" nacionalidade

spec :: Spec
spec = withApp $ do
    describe "CRUD de autor" $ do
        it "cadastra um autor pelo formulário e mostra na listagem" $ do
            get AutorNovoR
            statusIs 200
            enviarAutor AutoresR "Clarice Lispector" "Brasileira"
            statusIs 303
            autores <- runDB $ selectList [AutorNome ==. "Clarice Lispector"] []
            assertEq "um autor gravado" 1 (length autores)
            get AutoresR
            htmlAnyContain "td a" "Clarice Lispector"

        it "recusa nome em branco e não grava nada" $ do
            get AutorNovoR
            enviarAutor AutoresR "   " ""
            statusIs 200
            bodyContains "Não pode ficar em branco"
            autores <- runDB $ count ([] :: [Filter Autor])
            assertEq "nenhum autor gravado" 0 autores

        it "atualiza um autor existente" $ do
            autorId <- runDB $ insert $ Autor "Jorje Amado" Nothing
            get (AutorEditarR autorId)
            statusIs 200
            enviarAutor (AutorR autorId) "Jorge Amado" "Brasileira"
            statusIs 303
            autor <- runDB $ getJust autorId
            assertEq "nome corrigido" "Jorge Amado" (autorNome autor)

        it "exclui um autor sem livros" $ do
            autorId <- runDB $ insert $ Autor "Autor avulso" Nothing
            get (AutorR autorId)
            request $ do
                setMethod "POST"
                setUrl (AutorExcluirR autorId)
                addToken
            statusIs 303
            restante <- runDB $ count [AutorId ==. autorId]
            assertEq "autor removido" 0 restante

        it "não exclui autor que tem livros" $ do
            runDB popular
            autores <- runDB $ selectList [AutorNome ==. "Machado de Assis"] []
            autorId <- case autores of
                [Entity chave _] -> return chave
                _ -> error "seed sem Machado de Assis"
            get (AutorR autorId)
            request $ do
                setMethod "POST"
                setUrl (AutorExcluirR autorId)
                addToken
            statusIs 303
            restante <- runDB $ count [AutorId ==. autorId]
            assertEq "autor mantido" 1 restante
            _ <- followRedirect
            htmlAnyContain ".alert-danger" "ligado a 2 livro(s)"

        it "recusa POST sem token CSRF" $ do
            autorId <- runDB $ insert $ Autor "Protegido" Nothing
            request $ do
                setMethod "POST"
                setUrl (AutorExcluirR autorId)
            statusIs 403
