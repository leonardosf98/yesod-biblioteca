{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiNotificacao
    ( getApiNotificacoesR
    , postApiNotificacoesLeituraR
    , postApiNotificacaoLeituraR
    ) where

import Import

getApiNotificacoesR :: Handler Value
getApiNotificacoesR = do
    Entity userId _ <- exigirUsuario
    limite <- min 100 . max 1 . fromMaybe 20 . (>>= readMay) <$> lookupGetParam "limite"
    (naoLidas, notificacoes) <- runDB $ (,)
        <$> count [NotificacaoUserId ==. userId, NotificacaoLidaEm ==. Nothing]
        <*> selectList [NotificacaoUserId ==. userId] [Desc NotificacaoCriadaEm, Desc NotificacaoId, LimitTo limite]
    returnJson $ object
        [ "naoLidas" .= naoLidas
        , "notificacoes" .=
            [ object
                [ "id" .= k
                , "tipo" .= notificacaoTipo n
                , "titulo" .= notificacaoTitulo n
                , "texto" .= notificacaoTexto n
                , "link" .= notificacaoLink n
                , "criadaEm" .= notificacaoCriadaEm n
                , "lidaEm" .= notificacaoLidaEm n
                ]
            | Entity k n <- notificacoes
            ]
        ]

postApiNotificacaoLeituraR :: NotificacaoId -> Handler Value
postApiNotificacaoLeituraR notificacaoId = do
    Entity userId _ <- exigirUsuario
    agora <- liftIO getCurrentTime
    encontrada <- runDB $ get notificacaoId
    case encontrada of
        Just n | notificacaoUserId n == userId -> do
            runDB $ updateWhere [NotificacaoId ==. notificacaoId, NotificacaoLidaEm ==. Nothing] [NotificacaoLidaEm =. Just agora]
            sendResponseStatus status204 ()
        _ -> notFound

postApiNotificacoesLeituraR :: Handler Value
postApiNotificacoesLeituraR = do
    Entity userId _ <- exigirUsuario
    agora <- liftIO getCurrentTime
    runDB $ updateWhere [NotificacaoUserId ==. userId, NotificacaoLidaEm ==. Nothing] [NotificacaoLidaEm =. Just agora]
    sendResponseStatus status204 ()
