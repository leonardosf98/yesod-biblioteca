{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Ativacao
    ( postAtivacaoR
    , postSocioCodigoR
    ) where

import Import
import Api.Resposta
import Data.Aeson (withObject)
import Regras.Conta

data PedidoAtivacao = PedidoAtivacao Text Text Text

instance FromJSON PedidoAtivacao where
    parseJSON = withObject "PedidoAtivacao" $ \o ->
        PedidoAtivacao <$> o .: "email" <*> o .: "codigo" <*> o .: "senha"

postAtivacaoR :: Handler Value
postAtivacaoR = do
    PedidoAtivacao email codigo senha <- requireCheckJsonBody
    resultado <- runDB $ ativarConta email codigo senha
    case resultado of
        Right _ -> returnJson $ object ["login" .= toLower email]
        Left SenhaCurta -> sendStatusJSON status400 $ object
            [ "erro" .= ("A senha precisa ter pelo menos 8 caracteres." :: Text)
            , "campo" .= ("senha" :: Text)
            ]
        Left CodigoInvalido ->
            recusar status400 "E-mail ou código de ativação inválido ou vencido. Peça um código novo no balcão."

postSocioCodigoR :: SocioId -> Handler Value
postSocioCodigoR socioId = do
    (codigo, expiraEm) <- runDB $ get404 socioId >> gerarCodigoAtivacao socioId
    criado $ object ["codigo" .= codigo, "expiraEm" .= expiraEm]
