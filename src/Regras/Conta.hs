{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Conta
    ( ErroAtivacao (..)
    , gerarCodigoAtivacao
    , ativarConta
    , normalizarCodigo
    , salvarBibliotecario
    ) where

import ClassyPrelude.Yesod
import qualified Data.Text as T
import Data.Time (addUTCTime)
import Model
import Model.Tipos
import Regras.Politica (maximoTentativas, tamanhoMinimoSenha, validadeCodigoAtivacao)
import Token (codigoLegivel, hashToken)
import Yesod.Auth.HashDB (setPassword)

data ErroAtivacao = CodigoInvalido | SenhaCurta
    deriving (Eq, Show)

normalizarCodigo :: Text -> Text
normalizarCodigo = T.toUpper . T.filter (`notElem` ("- " :: String))

gerarCodigoAtivacao :: MonadIO m => SocioId -> ReaderT SqlBackend m (Text, UTCTime)
gerarCodigoAtivacao socioId = do
    codigo <- codigoLegivel 8 4
    agora <- liftIO getCurrentTime
    let expiraEm = addUTCTime validadeCodigoAtivacao agora
    deleteBy (UniqueCodigoAtivacaoSocio socioId)
    insert_ $ CodigoAtivacao socioId (hashToken (normalizarCodigo codigo)) expiraEm 0
    return (codigo, expiraEm)

ativarConta :: MonadIO m => Text -> Text -> Text -> ReaderT SqlBackend m (Either ErroAtivacao UserId)
ativarConta email codigo senha
    | T.length senha < tamanhoMinimoSenha = return (Left SenhaCurta)
    | otherwise = do
        agora <- liftIO getCurrentTime
        socio <- getBy (UniqueSocioEmail login)
        registro <- maybe (return Nothing) (getBy . UniqueCodigoAtivacaoSocio . entityKey) socio
        existente <- getBy (UniqueUser login)
        let contaDeBibliotecario = maybe False ((== PapelBibliotecario) . userPapel . entityVal) existente
        case (socio, registro) of
            (Just (Entity socioId _), Just (Entity registroId r))
                | contaDeBibliotecario
                    || codigoAtivacaoExpiraEm r <= agora
                    || codigoAtivacaoTentativas r >= maximoTentativas ->
                    return (Left CodigoInvalido)
                | codigoAtivacaoHash r /= hashToken (normalizarCodigo codigo) -> do
                    update registroId [CodigoAtivacaoTentativas +=. 1]
                    return (Left CodigoInvalido)
                | otherwise -> do
                    delete registroId
                    usuario <- setPassword senha (User login Nothing PapelSocio (Just socioId))
                    usuarioId <- gravarUsuario existente usuario
                    deleteWhere [SessaoUserId ==. usuarioId]
                    return (Right usuarioId)
            _ -> return (Left CodigoInvalido)
  where
    login = T.toLower (T.strip email)

salvarBibliotecario :: MonadIO m => Text -> Text -> ReaderT SqlBackend m UserId
salvarBibliotecario login senha = do
    usuario <- setPassword senha (User login Nothing PapelBibliotecario Nothing)
    existente <- getBy (UniqueUser login)
    gravarUsuario existente usuario

gravarUsuario :: MonadIO m => Maybe (Entity User) -> User -> ReaderT SqlBackend m UserId
gravarUsuario existente usuario = case existente of
    Just (Entity usuarioId _) -> replace usuarioId usuario >> return usuarioId
    Nothing -> insert usuario
