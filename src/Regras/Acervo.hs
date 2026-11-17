{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Acervo
    ( normalizarIsbn
    , gerarCodigoExemplar
    , gravarLivroExterno
    ) where

import ClassyPrelude.Yesod
import Data.Char (isDigit)
import qualified Data.Text as T
import Database.Persist.Sql (fromSqlKey)
import Integracao.OpenLibrary (LivroExterno (..))
import Model

normalizarIsbn :: Text -> Maybe Text
normalizarIsbn texto
    | T.length digitos `elem` [10, 13] && T.all valido digitos = Just digitos
    | otherwise = Nothing
  where
    digitos = T.toUpper (T.filter (`notElem` ("- " :: String)) texto)
    valido c = isDigit c || c == 'X'

gerarCodigoExemplar :: MonadIO m => LivroId -> ReaderT SqlBackend m Text
gerarCodigoExemplar livroId = do
    existentes <- count [ExemplarLivroId ==. livroId]
    let prefixo = "L" <> tshow (fromSqlKey livroId) <> "-"
        candidatos = [prefixo <> tshow n | n <- [existentes + 1 ..]]
    livres <- filterM (fmap isNothing . getBy . UniqueCodigo) (take 50 candidatos)
    maybe (error "sem código livre") return (headMay livres)

gravarLivroExterno :: MonadIO m => CategoriaId -> Text -> LivroExterno -> ReaderT SqlBackend m LivroId
gravarLivroExterno categoriaId isbn externo = do
    editoraId <- forM (externoEditora externo) $ \nome ->
        either entityKey id <$> insertBy (Editora nome Nothing)
    autores <- forM (externoAutores externo) $ \nome -> do
        existente <- selectFirst [AutorNome ==. nome] []
        maybe (insert (Autor nome Nothing)) (return . entityKey) existente
    livroId <- insert Livro
        { livroTitulo = externoTitulo externo
        , livroIsbn = Just isbn
        , livroAno = externoAno externo
        , livroSinopse = externoSinopse externo
        , livroCapaUrl = externoCapa externo
        , livroEditoraId = editoraId
        , livroCategoriaId = categoriaId
        }
    insertMany_ [LivroAutor livroId autorId | autorId <- ordNub autores]
    return livroId
