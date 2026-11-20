{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Token
    ( novoToken
    , hashToken
    , codigoLegivel
    ) where

import ClassyPrelude
import Crypto.Hash (SHA256 (..), hashWith)
import Crypto.Random (getRandomBytes)
import qualified Data.ByteString as B
import Data.ByteArray.Encoding (Base (Base64URLUnpadded), convertToBase)
import qualified Data.Text as T

novoToken :: IO Text
novoToken = do
    bytes <- getRandomBytes 32 :: IO ByteString
    return $ decodeUtf8 (convertToBase Base64URLUnpadded bytes :: ByteString)

hashToken :: Text -> Text
hashToken token = tshow (hashWith SHA256 (encodeUtf8 token :: ByteString))

-- Sem 0/O, 1/I: o código é lido em voz alta no balcão.
alfabetoLegivel :: Text
alfabetoLegivel = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

codigoLegivel :: MonadIO m => Int -> Int -> m Text
codigoLegivel tamanho posicaoDoHifen = do
    bytes <- liftIO (getRandomBytes tamanho :: IO ByteString)
    let letras = T.pack [letra b | b <- B.unpack bytes]
    return (T.take posicaoDoHifen letras <> "-" <> T.drop posicaoDoHifen letras)
  where
    letra b = T.index alfabetoLegivel (fromIntegral b `mod` T.length alfabetoLegivel)
