{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module ApiTeste
    ( entrarNaApi
    , campoDaResposta
    , tokenDaResposta
    , comToken
    , enviarJson
    , respostaJson
    ) where

import Data.Aeson (FromJSON, Value (Null), decode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key (fromText)
import Data.Aeson.Types (parseMaybe)
import Network.Wai.Test (simpleBody)
import TestImport

enviarJson :: Maybe Text -> Route App -> Value -> YesodExample App ()
enviarJson token rota corpo = request $ do
    setMethod "POST"
    setUrl rota
    addRequestHeader ("Accept", "application/json")
    addRequestHeader ("Content-Type", "application/json")
    forM_ token $ \t -> addRequestHeader ("Authorization", "Bearer " <> encodeUtf8 t)
    setRequestBody (encode corpo)

entrarNaApi :: Text -> Text -> YesodExample App ()
entrarNaApi login senha = enviarJson Nothing ApiSessoesR $ object ["login" .= login, "senha" .= senha]

campoDaResposta :: FromJSON a => Text -> YesodExample App (Maybe a)
campoDaResposta campo = do
    resposta <- getResponse
    return $ do
        corpo <- resposta
        valor <- decode (simpleBody corpo) :: Maybe Value
        parseMaybe (withObject "resposta" (.: fromText campo)) valor

tokenDaResposta :: YesodExample App Text
tokenDaResposta = campoDaResposta "token" >>= maybe (liftIO (expectationFailure "resposta sem token") >> return "") return

comToken :: Maybe Text -> Route App -> ByteString -> YesodExample App ()
comToken token rota metodo = request $ do
    setMethod metodo
    setUrl rota
    addRequestHeader ("Accept", "application/json")
    forM_ token $ \t -> addRequestHeader ("Authorization", "Bearer " <> encodeUtf8 t)

respostaJson :: YesodExample App Value
respostaJson = do
    resposta <- getResponse
    maybe (liftIO (expectationFailure "resposta sem JSON") >> return Null) return (resposta >>= decode . simpleBody)
