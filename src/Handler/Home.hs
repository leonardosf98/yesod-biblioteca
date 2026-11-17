{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Home where

import Import

getHomeR :: Handler Value
getHomeR = returnJson $ object
    [ "nome" .= ("API da Biblioteca" :: Text)
    , "documentacao" .= ("https://github.com/leonardosf98/yesod-biblioteca#api-rest" :: Text)
    ]
