{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.EditoraSpec (spec) where

import Seed (popular)
import TestImport

enviarEditora :: Route App -> Text -> Text -> YesodExample App ()
enviarEditora rota nome cidade = request $ do
    setMethod "POST"
    setUrl rota
    addToken
    byLabelExact "Nome" nome
    byLabelExact "Cidade" cidade

excluir :: EditoraId -> YesodExample App ()
excluir editoraId = do
    get (EditoraR editoraId)
    request $ do
        setMethod "POST"
        setUrl (EditoraExcluirR editoraId)
        addToken

spec :: Spec
spec = withApp $ do
    describe "CRUD de editora" $ do
        it "cadastra uma editora e mostra na listagem" $ do
            entrar
            get EditoraNovaR
            enviarEditora EditorasR "Rocco" "Rio de Janeiro"
            statusIs 303
            get EditorasR
            htmlAnyContain "td a" "Rocco"

        it "recusa nome repetido no cadastro" $ do
            entrar
            _ <- runDB $ insert $ Editora "Rocco" Nothing
            get EditoraNovaR
            enviarEditora EditorasR "Rocco" ""
            statusIs 200
            htmlAnyContain ".alert-danger" "Já existe uma editora com esse nome."
            total <- runDB $ count ([] :: [Filter Editora])
            assertEq "continua uma só" 1 total

        it "recusa renomear para um nome que já existe" $ do
            entrar
            _ <- runDB $ insert $ Editora "Rocco" Nothing
            outraId <- runDB $ insert $ Editora "Record" Nothing
            get (EditoraEditarR outraId)
            enviarEditora (EditoraR outraId) "Rocco" ""
            statusIs 200
            outra <- runDB $ getJust outraId
            assertEq "nome mantido" "Record" (editoraNome outra)

        it "atualiza mantendo o próprio nome" $ do
            entrar
            editoraId <- runDB $ insert $ Editora "Rocco" Nothing
            get (EditoraEditarR editoraId)
            enviarEditora (EditoraR editoraId) "Rocco" "Rio de Janeiro"
            statusIs 303
            editora <- runDB $ getJust editoraId
            assertEq "cidade gravada" (Just "Rio de Janeiro") (editoraCidade editora)

        it "exclui editora sem livros" $ do
            entrar
            editoraId <- runDB $ insert $ Editora "Sem livros" Nothing
            excluir editoraId
            statusIs 303
            restante <- runDB $ count [EditoraId ==. editoraId]
            assertEq "editora removida" 0 restante

        it "não exclui editora com livros" $ do
            entrar
            runDB popular
            editoras <- runDB $ selectList [EditoraNome ==. "Aleph"] []
            editoraId <- case editoras of
                [Entity chave _] -> return chave
                _ -> error "seed sem Aleph"
            excluir editoraId
            restante <- runDB $ count [EditoraId ==. editoraId]
            assertEq "editora mantida" 1 restante
