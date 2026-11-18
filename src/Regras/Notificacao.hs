{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Notificacao
    ( Aviso (..)
    , notificarUsuario
    , notificarSocio
    , notificarBibliotecarios
    , dataHoraLocal
    ) where

import ClassyPrelude.Yesod
import Data.Time (getTimeZone, utcToLocalTime)
import Model
import Model.Tipos

data Aviso = Aviso
    { avisoTipo :: Text
    , avisoChave :: Text
    , avisoTitulo :: Text
    , avisoTexto :: Text
    , avisoLink :: Maybe Text
    }

notificarUsuario :: MonadIO m => Aviso -> UserId -> ReaderT SqlBackend m ()
notificarUsuario aviso userId = do
    agora <- liftIO getCurrentTime
    void $ insertUnique Notificacao
        { notificacaoUserId = userId
        , notificacaoTipo = avisoTipo aviso
        , notificacaoChave = avisoChave aviso
        , notificacaoTitulo = avisoTitulo aviso
        , notificacaoTexto = avisoTexto aviso
        , notificacaoLink = avisoLink aviso
        , notificacaoCriadaEm = agora
        , notificacaoLidaEm = Nothing
        }

notificarSocio :: MonadIO m => SocioId -> Aviso -> ReaderT SqlBackend m ()
notificarSocio socioId aviso =
    selectKeysList [UserSocioId ==. Just socioId] [] >>= mapM_ (notificarUsuario aviso)

notificarBibliotecarios :: MonadIO m => Aviso -> ReaderT SqlBackend m ()
notificarBibliotecarios aviso =
    selectKeysList [UserPapel ==. PapelBibliotecario] [] >>= mapM_ (notificarUsuario aviso)

dataHoraLocal :: MonadIO m => UTCTime -> m Text
dataHoraLocal instante = liftIO $ do
    fuso <- getTimeZone instante
    return . pack . formatTime defaultTimeLocale "%d/%m às %H:%M" $ utcToLocalTime fuso instante
