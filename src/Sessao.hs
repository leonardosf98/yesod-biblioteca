{-# LANGUAGE NoImplicitPrelude #-}
module Sessao
    ( novoToken
    , hashToken
    , validadeSessao
    ) where

import ClassyPrelude
import Crypto.Hash (SHA256 (..), hashWith)
import Crypto.Random (getRandomBytes)
import Data.ByteArray.Encoding (Base (Base64URLUnpadded), convertToBase)
import Data.Time (NominalDiffTime)

validadeSessao :: NominalDiffTime
validadeSessao = 7 * 24 * 60 * 60

novoToken :: IO Text
novoToken = do
    bytes <- getRandomBytes 32 :: IO ByteString
    return $ decodeUtf8 (convertToBase Base64URLUnpadded bytes :: ByteString)

hashToken :: Text -> Text
hashToken token = tshow (hashWith SHA256 (encodeUtf8 token :: ByteString))
