{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Seed (popular) where

import ClassyPrelude.Yesod
import Data.Time (addDays)
import Model
import Model.Tipos
import Regras.Emprestimo (hoje)

popular :: MonadIO m => ReaderT SqlBackend m ()
popular = do
    categorias <- count ([] :: [Filter Categoria])
    when (categorias == 0) $ do
        dia <- hoje

        romance <- insert $ Categoria "Romance" (Just "Ficção em prosa")
        ficcao <- insert $ Categoria "Ficção científica" Nothing
        _ <- insert $ Categoria "Técnico" (Just "Programação e computação")

        companhia <- insert $ Editora "Companhia das Letras" (Just "São Paulo")
        aleph <- insert $ Editora "Aleph" (Just "São Paulo")

        machado <- insert $ Autor "Machado de Assis" (Just "Brasileira")
        asimov <- insert $ Autor "Isaac Asimov" (Just "Estadunidense")

        domCasmurro <- insert $ Livro "Dom Casmurro" Nothing (Just 1899) Nothing Nothing (Just companhia) romance
        bras <- insert $ Livro "Memórias Póstumas de Brás Cubas" Nothing (Just 1881) Nothing Nothing (Just companhia) romance
        euRobo <- insert $ Livro "Eu, Robô" Nothing (Just 1950) Nothing Nothing (Just aleph) ficcao
        fundacao <- insert $ Livro "Fundação" Nothing (Just 1951) Nothing Nothing (Just aleph) ficcao

        insertMany_
            [ LivroAutor domCasmurro machado
            , LivroAutor bras machado
            , LivroAutor euRobo asimov
            , LivroAutor fundacao asimov
            ]

        dc1 <- insert $ Exemplar domCasmurro "DC-001" Bom False
        _ <- insert $ Exemplar domCasmurro "DC-002" Danificado True
        br1 <- insert $ Exemplar bras "BC-001" Bom True
        _ <- insert $ Exemplar euRobo "ER-001" Bom True
        fu1 <- insert $ Exemplar fundacao "FU-001" Bom False

        ana <- insert $ Socio "Ana Souza" "ana@example.com" (Just "11999990000")
            (Just "01001000") (Just "Praça da Sé") (Just "100") (Just "Sé") (Just "São Paulo") (Just "SP")
        bruno <- insert $ Socio "Bruno Lima" "bruno@example.com" Nothing
            Nothing Nothing Nothing Nothing Nothing Nothing

        insertMany_
            [ Emprestimo dc1 ana (addDays (-20) dia) (addDays (-6) dia) Nothing 0
            , Emprestimo br1 bruno (addDays (-30) dia) (addDays (-16) dia) (Just (addDays (-14) dia)) 0
            , Emprestimo fu1 bruno (addDays (-3) dia) (addDays 11 dia) Nothing 0
            ]

        insert_ $ Reserva fundacao ana dia Ativa
