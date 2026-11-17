{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Integracao.ViaCep
    ( Endereco (..)
    , buscarCep
    , interpretarCep
    ) where

import ClassyPrelude.Yesod
import Control.Monad (mfilter)
import Data.Aeson (eitherDecode, withObject, (.:?))
import Data.Aeson.Types (parseEither)
import qualified Data.Text as T
import Network.HTTP.Simple
    ( getResponseBody
    , getResponseStatusCode
    , httpLBS
    , setRequestManager
    , setRequestResponseTimeout
    )

data Endereco = Endereco
    { enderecoLogradouro :: Maybe Text
    , enderecoBairro :: Maybe Text
    , enderecoCidade :: Text
    , enderecoUf :: Text
    }
    deriving (Show, Eq)

buscarCep :: Manager -> Text -> IO (Either Text Endereco)
buscarCep manager cep = do
    resultado <- try $ do
        requisicao <- parseRequest (unpack ("https://viacep.com.br/ws/" <> cep <> "/json/"))
        httpLBS
            $ setRequestManager manager
            $ setRequestResponseTimeout (responseTimeoutMicro 5000000)
            requisicao
    return $ case resultado of
        Left (_ :: HttpException) -> Left "Não foi possível consultar o CEP agora. Tente de novo ou deixe o CEP em branco."
        Right resposta
            | getResponseStatusCode resposta == 400 -> Left "CEP em formato inválido."
            | getResponseStatusCode resposta /= 200 -> Left "O ViaCEP respondeu com erro."
            | otherwise -> either (const (Left "Resposta inesperada do ViaCEP.")) interpretarCep
                (eitherDecode (getResponseBody resposta))

interpretarCep :: Value -> Either Text Endereco
interpretarCep valor = do
    campos <- either (const (Left "Resposta inesperada do ViaCEP.")) Right (parseEither leitor valor)
    case campos of
        (Just (_ :: Value), _, _, _, _) -> Left "CEP não encontrado."
        (Nothing, logradouro, bairro, Just cidade, Just uf) ->
            Right (Endereco (naoVazio logradouro) (naoVazio bairro) cidade uf)
        _ -> Left "Resposta inesperada do ViaCEP."
  where
    leitor = withObject "cep" $ \o -> (,,,,)
        <$> o .:? "erro"
        <*> o .:? "logradouro"
        <*> o .:? "bairro"
        <*> o .:? "localidade"
        <*> o .:? "uf"
    naoVazio = mfilter (not . T.null . T.strip)
