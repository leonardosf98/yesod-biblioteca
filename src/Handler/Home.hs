{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
module Handler.Home where

import Import

getHomeR :: Handler Html
getHomeR = do
    hoje <- utctDay <$> liftIO getCurrentTime
    (livros, disponiveis, socios, atrasados) <- runDB $ (,,,)
        <$> count ([] :: [Filter Livro])
        <*> count [ExemplarDisponivel ==. True]
        <*> count ([] :: [Filter Socio])
        <*> count [EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <. hoje]
    defaultLayout $ do
        setTitle "Biblioteca Comunitária"
        $(widgetFile "homepage")

contador :: Text -> Int -> Text -> Text -> Widget
contador titulo valor classe cor = [whamlet|
<div .col-sm-6 .col-md-3>
    <div class="panel panel-#{cor} contador #{classe}">
        <div .panel-heading>#{titulo}
        <div .panel-body>#{valor}
|]
