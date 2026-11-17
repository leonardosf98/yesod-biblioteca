{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.CategoriaSpec (spec) where

import Seed (popular)
import TestImport

enviarCategoria :: Route App -> Text -> Text -> YesodExample App ()
enviarCategoria rota nome descricao = request $ do
    setMethod "POST"
    setUrl rota
    addToken
    byLabelExact "Nome" nome
    byLabelExact "Descrição" descricao

excluir :: CategoriaId -> YesodExample App ()
excluir categoriaId = do
    get (CategoriaR categoriaId)
    request $ do
        setMethod "POST"
        setUrl (CategoriaExcluirR categoriaId)
        addToken

spec :: Spec
spec = withApp $ do
    describe "CRUD de categoria" $ do
        it "cadastra uma categoria com descrição" $ do
            entrar
            get CategoriaNovaR
            enviarCategoria CategoriasR "Poesia" "Versos e poemas"
            statusIs 303
            categorias <- runDB $ selectList [CategoriaNome ==. "Poesia"] []
            assertEq "descrição gravada" [Just "Versos e poemas"] (map (categoriaDescricao . entityVal) categorias)

        it "recusa nome repetido no cadastro" $ do
            entrar
            _ <- runDB $ insert $ Categoria "Poesia" Nothing
            get CategoriaNovaR
            enviarCategoria CategoriasR "Poesia" ""
            statusIs 200
            htmlAnyContain ".alert-danger" "Já existe uma categoria com esse nome."

        it "recusa renomear para um nome que já existe" $ do
            entrar
            _ <- runDB $ insert $ Categoria "Poesia" Nothing
            outraId <- runDB $ insert $ Categoria "Contos" Nothing
            get (CategoriaEditarR outraId)
            enviarCategoria (CategoriaR outraId) "Poesia" ""
            statusIs 200
            outra <- runDB $ getJust outraId
            assertEq "nome mantido" "Contos" (categoriaNome outra)

        it "exclui categoria sem livros" $ do
            entrar
            categoriaId <- runDB $ insert $ Categoria "Vazia" Nothing
            excluir categoriaId
            statusIs 303
            restante <- runDB $ count [CategoriaId ==. categoriaId]
            assertEq "categoria removida" 0 restante

        it "não exclui categoria com livros" $ do
            entrar
            runDB popular
            categorias <- runDB $ selectList [CategoriaNome ==. "Romance"] []
            categoriaId <- case categorias of
                [Entity chave _] -> return chave
                _ -> error "seed sem Romance"
            excluir categoriaId
            restante <- runDB $ count [CategoriaId ==. categoriaId]
            assertEq "categoria mantida" 1 restante
