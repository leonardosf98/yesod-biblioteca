{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Integracao.OpenLibrary
    ( LivroExterno (..)
    , ErroOpenLibrary (..)
    , buscarPorIsbn
    , interpretarResposta
    ) where

import ClassyPrelude.Yesod hiding (Proxy)
import Data.Aeson (eitherDecode, withObject, (.!=), (.:?))
import qualified Data.Aeson.Key as Key
import Data.Aeson.Types (Object, Parser, parseEither)
import Data.Char (isDigit)
import qualified Data.Text as T
import Network.HTTP.Simple
    ( addRequestHeader
    , getResponseBody
    , getResponseStatusCode
    , httpLBS
    , setRequestManager
    , setRequestResponseTimeout
    )

data LivroExterno = LivroExterno
    { externoTitulo :: Text
    , externoAutores :: [Text]
    , externoEditora :: Maybe Text
    , externoAno :: Maybe Int
    , externoCapa :: Maybe Text
    , externoSinopse :: Maybe Text
    }
    deriving (Show, Eq)

data ErroOpenLibrary
    = Indisponivel Text
    | NaoEncontrado
    deriving (Show, Eq)

buscarPorIsbn :: Manager -> Text -> IO (Either ErroOpenLibrary LivroExterno)
buscarPorIsbn manager isbn = do
    resultado <- try $ do
        requisicao <- parseRequest (unpack url)
        httpLBS
            $ setRequestManager manager
            $ setRequestResponseTimeout (responseTimeoutMicro 8000000)
            $ addRequestHeader "User-Agent" "biblioteca-comunitaria/0.1 (projeto academico)"
            requisicao
    return $ case resultado of
        Left (_ :: HttpException) -> Left (Indisponivel "Não foi possível falar com a Open Library. Tente de novo em instantes.")
        Right resposta
            | getResponseStatusCode resposta /= 200 -> Left (Indisponivel "A Open Library respondeu com erro.")
            | otherwise -> do
                valor <- either (const (Left (Indisponivel "Resposta inesperada da Open Library."))) Right
                    (eitherDecode (getResponseBody resposta))
                encontrado <- first Indisponivel (interpretarResposta isbn valor)
                maybe (Left NaoEncontrado) Right encontrado
  where
    url = "https://openlibrary.org/api/books?format=json&jscmd=data&bibkeys=ISBN:" <> isbn

interpretarResposta :: Text -> Value -> Either Text (Maybe LivroExterno)
interpretarResposta isbn = either (const (Left "Resposta inesperada da Open Library.")) Right . parseEither raiz
  where
    raiz = withObject "resposta" $ \objeto -> do
        dados <- objeto .:? Key.fromText ("ISBN:" <> isbn)
        traverse (withObject "livro" livro) dados

livro :: Object -> Parser LivroExterno
livro o = do
    titulo <- o .: "title"
    autores <- o .:? "authors" .!= [] >>= mapM (withObject "autor" (.: "name"))
    editoras <- o .:? "publishers" .!= [] >>= mapM (withObject "editora" (.: "name"))
    dataPublicacao <- o .:? "publish_date"
    capa <- o .:? "cover" >>= traverse (.:? "medium")
    trechos <- o .:? "excerpts" .!= [] >>= mapM (withObject "trecho" (.: "text"))
    return LivroExterno
        { externoTitulo = T.take 200 titulo
        , externoAutores = map (T.take 120) autores
        , externoEditora = T.take 120 <$> headMay editoras
        , externoAno = dataPublicacao >>= extrairAno
        , externoCapa = join capa
        , externoSinopse = headMay trechos
        }

extrairAno :: Text -> Maybe Int
extrairAno texto = headMay
    [ ano
    | palavra <- T.split (not . isDigit) texto
    , T.length palavra == 4
    , Just ano <- [readMay palavra]
    ]
