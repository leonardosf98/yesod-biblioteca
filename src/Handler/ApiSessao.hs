{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiSessao
    ( postApiSessoesR
    , deleteApiSessoesR
    , getApiEuR
    ) where

import Import
import Data.Aeson (withObject)
import Data.Time (addUTCTime)
import Sessao (hashToken, novoToken, validadeSessao)
import Yesod.Auth.HashDB (validatePass)

data Credenciais = Credenciais Text Text

instance FromJSON Credenciais where
    parseJSON = withObject "Credenciais" $ \o ->
        Credenciais <$> o .: "login" <*> o .: "senha"

postApiSessoesR :: Handler Value
postApiSessoesR = do
    Credenciais login senha <- requireCheckJsonBody
    usuario <- runDB $ getBy (UniqueUser login)
    case usuario of
        Just (Entity usuarioId u) | validatePass u senha == Just True -> do
            token <- liftIO novoToken
            agora <- liftIO getCurrentTime
            let expiraEm = addUTCTime validadeSessao agora
            runDB $ do
                deleteWhere [SessaoUserId ==. usuarioId, SessaoExpiraEm <=. agora]
                insert_ $ Sessao usuarioId (hashToken token) expiraEm
            sendStatusJSON status201 $ object
                [ "token" .= token
                , "expiraEm" .= expiraEm
                , "usuario" .= usuarioJson u
                ]
        _ -> sendStatusJSON status401 $ object ["erro" .= ("Login ou senha inválidos." :: Text)]

deleteApiSessoesR :: Handler Value
deleteApiSessoesR = do
    token <- lookupBearerAuth
    case token of
        Nothing -> sendStatusJSON status401 $ object ["erro" .= ("Sessão não informada." :: Text)]
        Just valor -> do
            runDB $ deleteBy (UniqueSessaoToken (hashToken valor))
            sendResponseStatus status204 ()

getApiEuR :: Handler Value
getApiEuR = do
    Entity _ u <- requireAuth
    returnJson (usuarioJson u)

usuarioJson :: User -> Value
usuarioJson u = object
    [ "login" .= userIdent u
    , "papel" .= case userPapel u of
        PapelBibliotecario -> "bibliotecario" :: Text
        PapelSocio -> "socio"
    ]
