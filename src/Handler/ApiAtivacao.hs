{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiAtivacao
    ( postApiAtivacaoR
    , postApiSocioCodigoR
    , postSocioCodigoR
    ) where

import Import
import Data.Aeson (withObject)
import Form.Comum (mensagem)
import Regras.Ativacao

data PedidoAtivacao = PedidoAtivacao Text Text Text

instance FromJSON PedidoAtivacao where
    parseJSON = withObject "PedidoAtivacao" $ \o ->
        PedidoAtivacao <$> o .: "email" <*> o .: "codigo" <*> o .: "senha"

postApiAtivacaoR :: Handler Value
postApiAtivacaoR = do
    PedidoAtivacao email codigo senha <- requireCheckJsonBody
    resultado <- runDB $ ativarConta email codigo senha
    case resultado of
        Right _ -> returnJson $ object ["login" .= toLower email]
        Left SenhaCurta -> sendStatusJSON status400 $ object
            ["erro" .= ("A senha precisa ter pelo menos 8 caracteres." :: Text), "campo" .= ("senha" :: Text)]
        Left CodigoInvalido -> sendStatusJSON status400 $ object
            ["erro" .= ("E-mail ou código de ativação inválido ou vencido. Peça um código novo no balcão." :: Text)]

postApiSocioCodigoR :: SocioId -> Handler Value
postApiSocioCodigoR socioId = do
    _ <- runDB $ get404 socioId
    (codigo, expiraEm) <- runDB $ gerarCodigoAtivacao socioId
    sendStatusJSON status201 $ object ["codigo" .= codigo, "expiraEm" .= expiraEm]

postSocioCodigoR :: SocioId -> Handler Html
postSocioCodigoR socioId = do
    _ <- runDB $ get404 socioId
    (codigo, expiraEm) <- runDB $ gerarCodigoAtivacao socioId
    mensagem "success" $ "Código de ativação: " <> codigo <> " (vale até " <> formatarData (utctDay expiraEm)
        <> "). Entregue ao sócio; ele ativa a conta em /ativar com o e-mail e esse código."
    redirect (SocioR socioId)
