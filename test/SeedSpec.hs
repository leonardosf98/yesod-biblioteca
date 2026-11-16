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

        it "exemplar emprestado fica indisponível" $ do
            runDB popular
            abertos <- runDB $ selectList [EmprestimoDataDevolucao ==. Nothing] []
            exemplares <- runDB $ mapM (getJust . emprestimoExemplarId . entityVal) abertos
            assertEq "todos indisponíveis" True (not (any exemplarDisponivel exemplares))
