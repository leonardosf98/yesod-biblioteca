{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Comum
    ( hoje
    , chaveDe
    , formatarCentavos
    , dataCurta
    , dataHoraLocal
    , tituloDoLivro
    , tituloDoExemplar
    ) where

import ClassyPrelude.Yesod
import Data.Time (getCurrentTimeZone, getTimeZone, localDay, utcToLocalTime)
import Database.Persist.Sql (fromSqlKey)
import Model

hoje :: MonadIO m => m Day
hoje = liftIO $ do
    fuso <- getCurrentTimeZone
    localDay . utcToLocalTime fuso <$> getCurrentTime

chaveDe :: ToBackendKey SqlBackend r => Key r -> Text
chaveDe = tshow . fromSqlKey

formatarCentavos :: Int -> Text
formatarCentavos centavos = "R$ " <> tshow reais <> "," <> (if resto < 10 then "0" else "") <> tshow resto
  where
    (reais, resto) = centavos `divMod` 100

dataCurta :: Day -> Text
dataCurta = pack . formatTime defaultTimeLocale "%d/%m"

dataHoraLocal :: MonadIO m => UTCTime -> m Text
dataHoraLocal instante = liftIO $ do
    fuso <- getTimeZone instante
    return . pack . formatTime defaultTimeLocale "%d/%m às %H:%M" $ utcToLocalTime fuso instante

tituloDoLivro :: MonadIO m => LivroId -> ReaderT SqlBackend m Text
tituloDoLivro livroId = maybe "livro" livroTitulo <$> get livroId

tituloDoExemplar :: MonadIO m => ExemplarId -> ReaderT SqlBackend m Text
tituloDoExemplar exemplarId = do
    exemplar <- get exemplarId
    maybe (return "livro") (tituloDoLivro . exemplarLivroId) exemplar
