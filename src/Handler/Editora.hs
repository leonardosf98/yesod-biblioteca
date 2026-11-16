{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Editora where

import Form.Comum
import Import

editoraForm :: Maybe Editora -> Form Editora
editoraForm atual = renderizar $ Editora
    <$> areq (textoLimitado 120) "Nome" (editoraNome <$> atual)
    <*> aopt (textoLimitado 80) "Cidade" (editoraCidade <$> atual)

nomeRepetido :: Text
nomeRepetido = "Já existe uma editora com esse nome."

getEditorasR :: Handler Html
getEditorasR = do
    editoras <- runDB $ selectList [] [Asc EditoraNome]
    defaultLayout $ do
        setTitle "Editoras"
        $(widgetFile "editoras/lista")

getEditoraNovaR :: Handler Html
getEditoraNovaR = do
    (formulario, enctype) <- generateFormPost (editoraForm Nothing)
    paginaFormulario "Nova editora" EditorasR formulario enctype

postEditorasR :: Handler Html
postEditorasR = do
    ((resultado, formulario), enctype) <- runFormPost (editoraForm Nothing)
    case resultado of
        FormSuccess editora -> do
            inserida <- runDB $ insertUnique editora
            case inserida of
                Just editoraId -> do
                    mensagem "success" "Editora cadastrada."
                    redirect (EditoraR editoraId)
                Nothing -> do
                    mensagem "danger" nomeRepetido
                    paginaFormulario "Nova editora" EditorasR formulario enctype
        _ -> paginaFormulario "Nova editora" EditorasR formulario enctype

getEditoraR :: EditoraId -> Handler Html
getEditoraR editoraId = do
    (editora, livros) <- runDB $ (,)
        <$> get404 editoraId
        <*> selectList [LivroEditoraId ==. Just editoraId] [Asc LivroTitulo]
    defaultLayout $ do
        setTitle (toHtml (editoraNome editora))
        $(widgetFile "editoras/detalhe")

getEditoraEditarR :: EditoraId -> Handler Html
getEditoraEditarR editoraId = do
    editora <- runDB $ get404 editoraId
    (formulario, enctype) <- generateFormPost (editoraForm (Just editora))
    paginaFormulario "Editar editora" (EditoraR editoraId) formulario enctype

postEditoraR :: EditoraId -> Handler Html
postEditoraR editoraId = do
    _ <- runDB $ get404 editoraId
    ((resultado, formulario), enctype) <- runFormPost (editoraForm Nothing)
    case resultado of
        FormSuccess editora -> do
            mesmoNome <- runDB $ getBy (UniqueEditoraNome (editoraNome editora))
            case mesmoNome of
                Just (Entity outraId _) | outraId /= editoraId -> do
                    mensagem "danger" nomeRepetido
                    paginaFormulario "Editar editora" (EditoraR editoraId) formulario enctype
                _ -> do
                    runDB $ replace editoraId editora
                    mensagem "success" "Editora atualizada."
                    redirect (EditoraR editoraId)
        _ -> paginaFormulario "Editar editora" (EditoraR editoraId) formulario enctype

postEditoraExcluirR :: EditoraId -> Handler Html
postEditoraExcluirR editoraId = do
    _ <- runDB $ get404 editoraId
    livros <- runDB $ count [LivroEditoraId ==. Just editoraId]
    if livros > 0
        then do
            mensagem "danger" ("Não é possível excluir: a editora tem " <> tshow livros <> " livro(s) no acervo.")
            redirect (EditoraR editoraId)
        else do
            runDB $ delete editoraId
            mensagem "success" "Editora excluída."
            redirect EditorasR
