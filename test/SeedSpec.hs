{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module SeedSpec (spec) where

import Data.Time (addDays)
import Regras.Comum (hoje)
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
                lusiadas <- selectKeysList [LivroTitulo ==. "Os Lusíadas"] []
                deleteWhere [ExemplarLivroId <-. lusiadas]
                deleteWhere [LivroId <-. lusiadas]
            runDB popular
            lusiadas <- runDB $ selectFirst [LivroTitulo ==. "Os Lusíadas"] []
            assertEq "Os Lusíadas voltou" True (isJust lusiadas)

        it "livros de domínio público vêm com capa, inclusive os do exemplo" $ do
            runDB popular
            dom <- runDB $ selectFirst [LivroTitulo ==. "Dom Casmurro"] []
            assertEq "Dom Casmurro com capa" True (isJust (dom >>= livroCapaUrl . entityVal))

        it "exemplar emprestado fica indisponível" $ do
            runDB popular
            abertos <- runDB $ selectList [EmprestimoDataDevolucao ==. Nothing] []
            exemplares <- runDB $ mapM (getJust . emprestimoExemplarId . entityVal) abertos
            assertEq "todos indisponíveis" True (not (any exemplarDisponivel exemplares))

        it "traz a circulação de demonstração com atrasos e vencimentos próximos" $ do
            runDB popular
            dia <- hoje
            socios <- runDB $ count ([] :: [Filter Socio])
            atrasados <- runDB $ count [EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <. dia]
            vencendo <- runDB $ count [EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista ==. addDays 2 dia]
            multasAbertas <- runDB $ count [EmprestimoMultaCentavos >. 0, EmprestimoMultaPagaEm ==. Nothing]
            reservas <- runDB $ count [ReservaStatus ==. Ativa]
            pedidos <- runDB $ count [PedidoStatus ==. PedidoAguardando]
            assertEq "doze sócios" 12 socios
            assertEq "três atrasados novos além do da Ana" 4 atrasados
            assertEq "quatro vencendo em dois dias" 4 vencendo
            assertEq "uma multa em aberto" 1 multasAbertas
            assertEq "três reservas ativas" 3 reservas
            assertEq "dois pedidos aguardando" 2 pedidos

        it "não duplica a circulação quando roda duas vezes" $ do
            runDB popular
            emprestimos <- runDB $ count ([] :: [Filter Emprestimo])
            runDB popular
            emprestimos' <- runDB $ count ([] :: [Filter Emprestimo])
            assertEq "mesma quantidade de empréstimos" emprestimos emprestimos'
