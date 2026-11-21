{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Api.Relacionados
    ( Relacionados
    , carregarRelacionados
    , socioResumo
    , livroResumo
    , livroDoExemplar
    , codigoDoExemplar
    , tituloDoLivro
    , tituloPeloExemplar
    , contarPorChave
    ) where

import Import
import qualified Data.Map.Strict as Map

data Relacionados = Relacionados
    { relSocios :: Map SocioId Socio
    , relExemplares :: Map ExemplarId Exemplar
    , relLivros :: Map LivroId Livro
    }

carregarRelacionados :: MonadIO m => [SocioId] -> [ExemplarId] -> [LivroId] -> ReaderT SqlBackend m Relacionados
carregarRelacionados socioIds exemplarIds livroIds = do
    socios <- selectList [SocioId <-. socioIds] []
    exemplares <- selectList [ExemplarId <-. exemplarIds] []
    livros <- selectList [LivroId <-. livroIds ++ map (exemplarLivroId . entityVal) exemplares] []
    return Relacionados
        { relSocios = porChave socios
        , relExemplares = porChave exemplares
        , relLivros = porChave livros
        }
  where
    porChave registros = Map.fromList [(k, v) | Entity k v <- registros]

socioResumo :: Relacionados -> SocioId -> Value
socioResumo rel socioId = object
    [ "id" .= socioId
    , "nome" .= maybe "—" socioNome (Map.lookup socioId (relSocios rel))
    ]

livroResumo :: Relacionados -> LivroId -> Value
livroResumo rel livroId = object
    [ "id" .= livroId
    , "titulo" .= fromMaybe "—" (tituloDoLivro rel livroId)
    , "capaUrl" .= (Map.lookup livroId (relLivros rel) >>= livroCapaUrl)
    ]

livroDoExemplar :: Relacionados -> ExemplarId -> Value
livroDoExemplar rel exemplarId =
    maybe (object []) (livroResumo rel . exemplarLivroId) (Map.lookup exemplarId (relExemplares rel))

codigoDoExemplar :: Relacionados -> ExemplarId -> Maybe Text
codigoDoExemplar rel exemplarId = exemplarCodigo <$> Map.lookup exemplarId (relExemplares rel)

tituloDoLivro :: Relacionados -> LivroId -> Maybe Text
tituloDoLivro rel livroId = livroTitulo <$> Map.lookup livroId (relLivros rel)

tituloPeloExemplar :: Relacionados -> ExemplarId -> Maybe Text
tituloPeloExemplar rel exemplarId =
    Map.lookup exemplarId (relExemplares rel) >>= tituloDoLivro rel . exemplarLivroId

contarPorChave :: Ord k => [k] -> Map k Int
contarPorChave chaves = Map.fromListWith (+) [(k, 1) | k <- chaves]
