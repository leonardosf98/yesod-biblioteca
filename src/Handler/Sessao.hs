{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Sessao
    ( postSessoesR
    , deleteSessoesR
    , getEuR
    ) where

import Import
import Api.Resposta
import Data.Aeson (withObject)
import Data.Time (addUTCTime)
import Regras.Politica (validadeSessao)
import Token (hashToken, novoToken)
import Yesod.Auth.HashDB (validatePass)

data Credenciais = Credenciais Text Text

instance FromJSON Credenciais where
    parseJSON = withObject "Credenciais" $ \o ->
        Credenciais <$> o .: "login" <*> o .: "senha"

postSessoesR :: Handler Value
postSessoesR = do
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
            criado $ object
                [ "token" .= token
                , "expiraEm" .= expiraEm
                , "usuario" .= usuarioJson u
                ]
        _ -> recusar status401 "Login ou senha inválidos."

deleteSessoesR :: Handler Value
deleteSessoesR = do
    token <- lookupBearerAuth
    case token of
        Nothing -> recusar status401 "Sessão não informada."
        Just valor -> do
            runDB $ deleteBy (UniqueSessaoToken (hashToken valor))
            semConteudo

getEuR :: Handler Value
getEuR = do
    Entity _ u <- exigirUsuario
    returnJson (usuarioJson u)

usuarioJson :: User -> Value
usuarioJson u = object
    [ "login" .= userIdent u
    , "papel" .= case userPapel u of
        PapelBibliotecario -> "bibliotecario" :: Text
        PapelSocio -> "socio"
    ]
