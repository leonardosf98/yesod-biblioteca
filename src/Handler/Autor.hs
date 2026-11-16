{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Autor where

import Form.Comum
import Import

autorForm :: Maybe Autor -> Form Autor
autorForm atual = renderizar $ Autor
    <$> areq (textoLimitado 120) "Nome" (autorNome <$> atual)
    <*> aopt (textoLimitado 60) "Nacionalidade" (autorNacionalidade <$> atual)

getAutoresR :: Handler Html
getAutoresR = do
    autores <- runDB $ selectList [] [Asc AutorNome]
    defaultLayout $ do
        setTitle "Autores"
        $(widgetFile "autores/lista")

getAutorNovoR :: Handler Html
getAutorNovoR = do
    (formulario, enctype) <- generateFormPost (autorForm Nothing)
    paginaFormulario "Novo autor" AutoresR formulario enctype

postAutoresR :: Handler Html
postAutoresR = do
    ((resultado, formulario), enctype) <- runFormPost (autorForm Nothing)
    case resultado of
        FormSuccess autor -> do
            autorId <- runDB $ insert autor
            mensagem "success" "Autor cadastrado."
            redirect (AutorR autorId)
        _ -> paginaFormulario "Novo autor" AutoresR formulario enctype

getAutorR :: AutorId -> Handler Html
getAutorR autorId = do
    (autor, livros) <- runDB $ do
        autor <- get404 autorId
        vinculos <- selectList [LivroAutorAutorId ==. autorId] []
        livros <- selectList [LivroId <-. map (livroAutorLivroId . entityVal) vinculos] [Asc LivroTitulo]
        return (autor, livros)
    defaultLayout $ do
        setTitle (toHtml (autorNome autor))
        $(widgetFile "autores/detalhe")

getAutorEditarR :: AutorId -> Handler Html
getAutorEditarR autorId = do
    autor <- runDB $ get404 autorId
    (formulario, enctype) <- generateFormPost (autorForm (Just autor))
    paginaFormulario "Editar autor" (AutorR autorId) formulario enctype

postAutorR :: AutorId -> Handler Html
postAutorR autorId = do
    _ <- runDB $ get404 autorId
    ((resultado, formulario), enctype) <- runFormPost (autorForm Nothing)
    case resultado of
        FormSuccess autor -> do
            runDB $ replace autorId autor
            mensagem "success" "Autor atualizado."
            redirect (AutorR autorId)
        _ -> paginaFormulario "Editar autor" (AutorR autorId) formulario enctype

postAutorExcluirR :: AutorId -> Handler Html
postAutorExcluirR autorId = do
    _ <- runDB $ get404 autorId
    livros <- runDB $ count [LivroAutorAutorId ==. autorId]
    if livros > 0
        then do
            mensagem "danger" ("Não é possível excluir: o autor está ligado a " <> tshow livros <> " livro(s).")
            redirect (AutorR autorId)
        else do
            runDB $ delete autorId
            mensagem "success" "Autor excluído."
            redirect AutoresR
