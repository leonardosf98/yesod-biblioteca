{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Integracao.OpenLibrarySpec (spec) where

import Data.Aeson (decode)
import Handler.LivroImportar (gravarLivroExterno)
import Integracao.OpenLibrary
import TestImport

respostaEncontrada :: LByteString
respostaEncontrada = "{\"ISBN:9780140328721\": {\"title\": \"Fantastic Mr. Fox\", \"authors\": [{\"name\": \"Roald Dahl\", \"url\": \"x\"}], \"publishers\": [{\"name\": \"Puffin\"}], \"publish_date\": \"October 1, 1988\", \"cover\": {\"small\": \"s.jpg\", \"medium\": \"m.jpg\"}, \"excerpts\": [{\"text\": \"Down in the valley there were three farms.\"}]}}"

esperado :: LivroExterno
esperado = LivroExterno
    { externoTitulo = "Fantastic Mr. Fox"
    , externoAutores = ["Roald Dahl"]
    , externoEditora = Just "Puffin"
    , externoAno = Just 1988
    , externoCapa = Just "m.jpg"
    , externoSinopse = Just "Down in the valley there were three farms."
    }

interpretar :: Text -> LByteString -> Either Text (Maybe LivroExterno)
interpretar isbn corpo = maybe (Left "json inválido") (interpretarResposta isbn) (decode corpo)

spec :: Spec
spec = do
    describe "interpretarResposta" $ do
        it "extrai título, autores, editora, ano, capa e trecho" $
            interpretar "9780140328721" respostaEncontrada `shouldBe` Right (Just esperado)

        it "devolve Nothing quando a Open Library responde {}" $
            interpretar "9789999999999" "{}" `shouldBe` Right Nothing

        it "aceita livro só com título" $
            interpretar "1" "{\"ISBN:1\": {\"title\": \"Apenas titulo\", \"publish_date\": \"sem data\"}}"
                `shouldBe` Right (Just (LivroExterno "Apenas titulo" [] Nothing Nothing Nothing Nothing))

        it "recusa resposta sem título" $
            interpretar "1" "{\"ISBN:1\": {\"authors\": []}}" `shouldBe` Left "Resposta inesperada da Open Library."

    withApp $ describe "gravarLivroExterno" $ do
        it "reaproveita editora e autor existentes e cria os vínculos" $ do
            (categoriaId, editoraId, autorId) <- runDB $ (,,)
                <$> insert (Categoria "Infantil" Nothing)
                <*> insert (Editora "Puffin" Nothing)
                <*> insert (Autor "Roald Dahl" Nothing)
            livroId <- runDB $ gravarLivroExterno categoriaId "9780140328721" esperado
            livro <- runDB $ getJust livroId
            assertEq "editora reaproveitada" (Just editoraId) (livroEditoraId livro)
            vinculos <- runDB $ selectList [LivroAutorLivroId ==. livroId] []
            assertEq "autor reaproveitado" [autorId] (map (livroAutorAutorId . entityVal) vinculos)
            totais <- runDB $ (,) <$> count ([] :: [Filter Editora]) <*> count ([] :: [Filter Autor])
            assertEq "nada duplicado" (1, 1) totais

        it "cria editora e autores que ainda não existem" $ do
            categoriaId <- runDB $ insert (Categoria "Infantil" Nothing)
            livroId <- runDB $ gravarLivroExterno categoriaId "9780140328721" esperado { externoAutores = ["A", "B", "A"] }
            vinculos <- runDB $ count [LivroAutorLivroId ==. livroId]
            assertEq "dois autores distintos" 2 vinculos
            editoras <- runDB $ count [EditoraNome ==. "Puffin"]
            assertEq "editora criada" 1 editoras
