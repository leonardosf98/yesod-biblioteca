{-# LANGUAGE NoImplicitPrelude #-}
module Usuario
    ( salvarBibliotecario
    ) where

import ClassyPrelude.Yesod
import Model
import Model.Tipos
import Yesod.Auth.HashDB (setPassword)

salvarBibliotecario :: MonadIO m => Text -> Text -> ReaderT SqlBackend m UserId
salvarBibliotecario login senha = do
    usuario <- setPassword senha (User login Nothing PapelBibliotecario Nothing)
    existente <- getBy (UniqueUser login)
    case existente of
        Just (Entity usuarioId _) -> replace usuarioId usuario >> return usuarioId
        Nothing -> insert usuario
