{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
module Api.Resposta
    ( criado
    , semConteudo
    , recusar
    , conflito
    , ouConflito
    , garantirUnico
    ) where

import Import

criado :: ToJSON v => v -> Handler a
criado = sendStatusJSON status201

semConteudo :: Handler a
semConteudo = sendResponseStatus status204 ()

recusar :: MonadHandler m => Status -> Text -> m a
recusar status mensagem = sendStatusJSON status $ object ["erro" .= mensagem]

conflito :: MonadHandler m => Text -> m a
conflito = recusar status409

ouConflito :: MonadHandler m => Either Text a -> m a
ouConflito = either conflito return

garantirUnico
    :: PersistRecordBackend r SqlBackend
    => Unique r -> Maybe (Key r) -> Text -> Handler ()
garantirUnico chaveUnica proprio mensagem = do
    existente <- runDB $ getBy chaveUnica
    when (maybe False ((/= proprio) . Just . entityKey) existente) $ conflito mensagem
