{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ExemplarSpec (spec) where

import Database.Persist.Sql (fromSqlKey)
import Seed (popular)
import TestImport

criarLivro :: YesodExample App LivroId
criarLivro = runDB $ do
    categoriaId <- insert (Categoria "Romance" Nothing)
    insert (Livro "Livro" Nothing Nothing Nothing Nothing Nothing categoriaId)

enviarExemplar :: Route App -> Text -> Text -> YesodExample App ()
enviarExemplar rota codigo estado = request $ do
    setMethod "POST"
    setUrl rota
    addToken_ ".form-principal"
    byLabelExact "Código (em branco para gerar)" codigo
    byLabelExact "Estado" estado

exemplarPorCodigo :: Text -> YesodExample App (Entity Exemplar)
exemplarPorCodigo codigo = do
    encontrado <- runDB $ getBy (UniqueCodigo codigo)
    maybe (error ("sem exemplar " <> unpack codigo)) return encontrado

spec :: Spec
spec = withApp $ do
    describe "Exemplares" $ do
        it "cadastra exemplar com código informado e disponível" $ do
            entrar
            livroId <- criarLivro
            get (ExemplarNovoR livroId)
            enviarExemplar (ExemplaresR livroId) "ABC-1" "1"
            statusIs 303
            Entity _ exemplar <- exemplarPorCodigo "ABC-1"
            assertEq "estado Bom" Bom (exemplarEstado exemplar)
            assertEq "disponível" True (exemplarDisponivel exemplar)

        it "gera código quando fica em branco" $ do
            entrar
            livroId <- criarLivro
            get (ExemplarNovoR livroId)
            enviarExemplar (ExemplaresR livroId) "" "1"
            get (ExemplarNovoR livroId)
            enviarExemplar (ExemplaresR livroId) "" "1"
            let prefixo = "L" <> tshow (fromSqlKey livroId) <> "-"
            _ <- exemplarPorCodigo (prefixo <> "1")
            _ <- exemplarPorCodigo (prefixo <> "2")
            return ()

        it "recusa código repetido" $ do
            entrar
            livroId <- criarLivro
            runDB $ insert_ (Exemplar livroId "ABC-1" Bom True)
            get (ExemplarNovoR livroId)
            enviarExemplar (ExemplaresR livroId) "ABC-1" "1"
            statusIs 200
            htmlAnyContain ".alert-danger" "Já existe um exemplar com esse código."

        it "altera o estado mantendo o código quando fica em branco" $ do
            entrar
            livroId <- criarLivro
            exemplarId <- runDB $ insert (Exemplar livroId "ABC-1" Bom True)
            get (ExemplarEditarR exemplarId)
            enviarExemplar (ExemplarR exemplarId) "" "2"
            statusIs 303
            exemplar <- runDB $ getJust exemplarId
            assertEq "código mantido" "ABC-1" (exemplarCodigo exemplar)
            assertEq "agora danificado" Danificado (exemplarEstado exemplar)

        it "exclui exemplar sem empréstimos" $ do
            entrar
            livroId <- criarLivro
            exemplarId <- runDB $ insert (Exemplar livroId "ABC-1" Bom True)
            get (ExemplarEditarR exemplarId)
            request $ do
                setMethod "POST"
                setUrl (ExemplarExcluirR exemplarId)
                addToken_ ".form-excluir"
            statusIs 303
            restante <- runDB $ count [ExemplarId ==. exemplarId]
            assertEq "removido" 0 restante

        it "não exclui exemplar com empréstimos" $ do
            entrar
            runDB popular
            Entity exemplarId _ <- exemplarPorCodigo "DC-001"
            get (ExemplarEditarR exemplarId)
            request $ do
                setMethod "POST"
                setUrl (ExemplarExcluirR exemplarId)
                addToken_ ".form-excluir"
            restante <- runDB $ count [ExemplarId ==. exemplarId]
            assertEq "mantido" 1 restante
