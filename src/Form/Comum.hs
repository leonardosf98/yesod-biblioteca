{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Form.Comum
    ( textoLimitado
    , renderizar
    , paginaFormulario
    , botaoExcluir
    , mensagem
    ) where

import Import
import qualified Data.Text as T
import Yesod.Form.Bootstrap3 (BootstrapFormLayout (..), renderBootstrap3)

textoLimitado :: Int -> Field Handler Text
textoLimitado limite = check validar textField
  where
    validar texto
        | null limpo = Left ("Não pode ficar em branco" :: Text)
        | length limpo > limite = Left ("Use no máximo " <> tshow limite <> " caracteres")
        | otherwise = Right limpo
      where
        limpo = T.strip texto

renderizar :: AForm Handler a -> Form a
renderizar = renderBootstrap3 BootstrapBasicForm

paginaFormulario :: Text -> Route App -> Widget -> Enctype -> Handler Html
paginaFormulario titulo acao formulario enctype = defaultLayout $ do
    setTitle (toHtml titulo)
    [whamlet|
<h1>#{titulo}
<form method=post action=@{acao} enctype=#{enctype}>
    ^{formulario}
    <button .btn .btn-primary type=submit>Salvar
|]

botaoExcluir :: Route App -> Widget
botaoExcluir rota = do
    token <- reqToken <$> getRequest
    [whamlet|
<form .form-excluir method=post action=@{rota} onsubmit="return confirm('Excluir este registro?')">
    $maybe valor <- token
        <input type=hidden name=#{defaultCsrfParamName} value=#{valor}>
    <button .btn .btn-danger type=submit>Excluir
|]

mensagem :: Text -> Text -> Handler ()
mensagem status texto = addMessage status (toHtml texto)
