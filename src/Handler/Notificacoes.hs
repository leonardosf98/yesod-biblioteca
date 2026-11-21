{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Notificacoes
    ( getNotificacoesR
    , postNotificacoesLeituraR
    , postNotificacaoLeituraR
    ) where

import Import
import Api.Filtro (parametroInteiro)
import Api.Resposta (semConteudo)

getNotificacoesR :: Handler Value
getNotificacoesR = do
    Entity userId _ <- exigirUsuario
    limite <- parametroInteiro "limite" 20 (1, 100)
    (naoLidas, notificacoes) <- runDB $ (,)
        <$> count [NotificacaoUserId ==. userId, NotificacaoLidaEm ==. Nothing]
        <*> selectList [NotificacaoUserId ==. userId] [Desc NotificacaoCriadaEm, Desc NotificacaoId, LimitTo limite]
    returnJson $ object
        [ "naoLidas" .= naoLidas
        , "notificacoes" .= map notificacaoJson notificacoes
        ]

postNotificacaoLeituraR :: NotificacaoId -> Handler Value
postNotificacaoLeituraR notificacaoId = do
    Entity userId _ <- exigirUsuario
    encontrada <- runDB $ get notificacaoId
    case encontrada of
        Just n | notificacaoUserId n == userId -> do
            marcarComoLidas [NotificacaoId ==. notificacaoId]
            semConteudo
        _ -> notFound

postNotificacoesLeituraR :: Handler Value
postNotificacoesLeituraR = do
    Entity userId _ <- exigirUsuario
    marcarComoLidas [NotificacaoUserId ==. userId]
    semConteudo

marcarComoLidas :: [Filter Notificacao] -> Handler ()
marcarComoLidas filtro = do
    agora <- liftIO getCurrentTime
    runDB $ updateWhere ((NotificacaoLidaEm ==. Nothing) : filtro) [NotificacaoLidaEm =. Just agora]

notificacaoJson :: Entity Notificacao -> Value
notificacaoJson (Entity k n) = object
    [ "id" .= k
    , "tipo" .= notificacaoTipo n
    , "titulo" .= notificacaoTitulo n
    , "texto" .= notificacaoTexto n
    , "link" .= notificacaoLink n
    , "criadaEm" .= notificacaoCriadaEm n
    , "lidaEm" .= notificacaoLidaEm n
    ]
