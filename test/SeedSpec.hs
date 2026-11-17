{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module SeedSpec (spec) where

import Seed (popular)
import TestImport

spec :: Spec
spec = withApp $ do
    describe "Seed" $ do
        it "popula todas as tabelas do domínio" $ do
            runDB popular
            contagens <- runDB $ sequence
                [ count ([] :: [Filter Autor])
                , count ([] :: [Filter Editora])
                , count ([] :: [Filter Categoria])
                , count ([] :: [Filter Livro])
                , count ([] :: [Filter LivroAutor])
                , count ([] :: [Filter Exemplar])
                , count ([] :: [Filter Socio])
                , count ([] :: [Filter Emprestimo])
                , count ([] :: [Filter Reserva])
                ]
            assertEq "nenhuma tabela vazia" True (all (> 0) contagens)

        it "não duplica dados quando roda duas vezes" $ do
            runDB popular
            livros <- runDB $ count ([] :: [Filter Livro])
            runDB popular
            livros' <- runDB $ count ([] :: [Filter Livro])
            assertEq "mesma quantidade de livros" livros livros'

        it "traz acervo suficiente para paginar o catálogo" $ do
            runDB popular
            livros <- runDB $ count ([] :: [Filter Livro])
            assertEq "pelo menos 40 livros" True (livros >= 40)

        it "acrescenta o acervo num banco que já tinha o exemplo" $ do
            runDB popular
            runDB $ do
                duna <- selectKeysList [LivroTitulo ==. "Duna"] []
                deleteWhere [ExemplarLivroId <-. duna]
                deleteWhere [LivroId <-. duna]
            runDB popular
            duna <- runDB $ selectFirst [LivroTitulo ==. "Duna"] []
            assertEq "Duna voltou" True (isJust duna)

        it "livros do Gutenberg vêm com capa, inclusive os do exemplo" $ do
            runDB popular
            dom <- runDB $ selectFirst [LivroTitulo ==. "Dom Casmurro"] []
            assertEq "Dom Casmurro com capa" True (isJust (dom >>= livroCapaUrl . entityVal))

        it "exemplar emprestado fica indisponível" $ do
            runDB popular
            abertos <- runDB $ selectList [EmprestimoDataDevolucao ==. Nothing] []
            exemplares <- runDB $ mapM (getJust . emprestimoExemplarId . entityVal) abertos
            assertEq "todos indisponíveis" True (not (any exemplarDisponivel exemplares))
