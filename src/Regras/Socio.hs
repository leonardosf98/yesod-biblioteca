{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Socio
    ( somenteDigitos
    , completarEndereco
    ) where

import ClassyPrelude.Yesod
import Data.Char (isDigit)
import qualified Data.Text as T
import Integracao.ViaCep
import Model

somenteDigitos :: [Int] -> Text -> Maybe Text
somenteDigitos tamanhos texto
    | T.length limpo `elem` tamanhos && T.all isDigit limpo = Just limpo
    | otherwise = Nothing
  where
    limpo = T.filter (`notElem` (" -()." :: String)) texto

completarEndereco :: Manager -> Maybe Socio -> Socio -> IO (Either Text Socio)
completarEndereco manager anterior socio = case socioCep socio of
    Nothing -> return (Right semEndereco)
    Just cep
        | Just cep == (anterior >>= socioCep) -> return (Right (copiarDe anterior))
        | otherwise -> fmap comEndereco <$> buscarCep manager cep
  where
    semEndereco = socio { socioLogradouro = Nothing, socioBairro = Nothing, socioCidade = Nothing, socioUf = Nothing }
    copiarDe origem = socio
        { socioLogradouro = origem >>= socioLogradouro
        , socioBairro = origem >>= socioBairro
        , socioCidade = origem >>= socioCidade
        , socioUf = origem >>= socioUf
        }
    comEndereco endereco = socio
        { socioLogradouro = enderecoLogradouro endereco
        , socioBairro = enderecoBairro endereco
        , socioCidade = Just (enderecoCidade endereco)
        , socioUf = Just (enderecoUf endereco)
        }
