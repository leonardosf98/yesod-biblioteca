{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Ativacao
    ( ErroAtivacao (..)
    , gerarCodigoAtivacao
    , ativarConta
    , normalizarCodigo
    , maximoTentativas
    ) where

import ClassyPrelude.Yesod
import qualified Data.ByteString as B
import qualified Data.Text as T
import Crypto.Random (getRandomBytes)
import Data.Time (NominalDiffTime, addUTCTime)
import Model
import Model.Tipos
import Sessao (hashToken)
import Yesod.Auth.HashDB (setPassword)

data ErroAtivacao = CodigoInvalido | SenhaCurta
    deriving (Eq, Show)

validadeCodigo :: NominalDiffTime
validadeCodigo = 7 * 24 * 60 * 60

maximoTentativas :: Int
maximoTentativas = 5

alfabeto :: Text
alfabeto = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

normalizarCodigo :: Text -> Text
normalizarCodigo = T.toUpper . T.filter (`notElem` ("- " :: String))

gerarCodigoAtivacao :: MonadIO m => SocioId -> ReaderT SqlBackend m (Text, UTCTime)
gerarCodigoAtivacao socioId = do
    bytes <- liftIO (getRandomBytes 8 :: IO ByteString)
    agora <- liftIO getCurrentTime
    let letras = T.pack [T.index alfabeto (fromIntegral b `mod` T.length alfabeto) | b <- B.unpack bytes]
        codigo = T.take 4 letras <> "-" <> T.drop 4 letras
        expiraEm = addUTCTime validadeCodigo agora
    deleteBy (UniqueCodigoAtivacaoSocio socioId)
    insert_ $ CodigoAtivacao socioId (hashToken (normalizarCodigo codigo)) expiraEm 0
    return (codigo, expiraEm)

ativarConta :: MonadIO m => Text -> Text -> Text -> ReaderT SqlBackend m (Either ErroAtivacao UserId)
ativarConta email codigo senha
    | T.length senha < 8 = return (Left SenhaCurta)
    | otherwise = do
        agora <- liftIO getCurrentTime
        socio <- getBy (UniqueSocioEmail (T.toLower (T.strip email)))
        registro <- maybe (return Nothing) (getBy . UniqueCodigoAtivacaoSocio . entityKey) socio
        case (socio, registro) of
            (Just (Entity socioId _), Just (Entity registroId r))
                | codigoAtivacaoExpiraEm r <= agora || codigoAtivacaoTentativas r >= maximoTentativas ->
                    return (Left CodigoInvalido)
                | codigoAtivacaoHash r /= hashToken (normalizarCodigo codigo) -> do
                    update registroId [CodigoAtivacaoTentativas +=. 1]
                    return (Left CodigoInvalido)
                | otherwise -> do
                    delete registroId
                    Right <$> criarOuRedefinir socioId
            _ -> return (Left CodigoInvalido)
  where
    login = T.toLower (T.strip email)
    criarOuRedefinir socioId = do
        usuario <- setPassword senha (User login Nothing PapelSocio (Just socioId))
        existente <- getBy (UniqueUser login)
        case existente of
            Just (Entity usuarioId _) -> do
                replace usuarioId usuario
                deleteWhere [SessaoUserId ==. usuarioId]
                return usuarioId
            Nothing -> insert usuario
