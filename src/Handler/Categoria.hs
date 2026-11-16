{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Categoria where

import Form.Comum
import Import

categoriaForm :: Maybe Categoria -> Form Categoria
categoriaForm atual = renderizar $ Categoria
    <$> areq (textoLimitado 60) "Nome" (categoriaNome <$> atual)
    <*> (fmap unTextarea <$> aopt textareaField "Descrição" (fmap Textarea . categoriaDescricao <$> atual))

nomeRepetido :: Text
nomeRepetido = "Já existe uma categoria com esse nome."

getCategoriasR :: Handler Html
getCategoriasR = do
    categorias <- runDB $ selectList [] [Asc CategoriaNome]
    defaultLayout $ do
        setTitle "Categorias"
        $(widgetFile "categorias/lista")

getCategoriaNovaR :: Handler Html
getCategoriaNovaR = do
    (formulario, enctype) <- generateFormPost (categoriaForm Nothing)
    paginaFormulario "Nova categoria" CategoriasR formulario enctype

postCategoriasR :: Handler Html
postCategoriasR = do
    ((resultado, formulario), enctype) <- runFormPost (categoriaForm Nothing)
    case resultado of
        FormSuccess categoria -> do
            inserida <- runDB $ insertUnique categoria
            case inserida of
                Just categoriaId -> do
                    mensagem "success" "Categoria cadastrada."
                    redirect (CategoriaR categoriaId)
                Nothing -> do
                    mensagem "danger" nomeRepetido
                    paginaFormulario "Nova categoria" CategoriasR formulario enctype
        _ -> paginaFormulario "Nova categoria" CategoriasR formulario enctype

getCategoriaR :: CategoriaId -> Handler Html
getCategoriaR categoriaId = do
    (categoria, livros) <- runDB $ (,)
        <$> get404 categoriaId
        <*> selectList [LivroCategoriaId ==. categoriaId] [Asc LivroTitulo]
    defaultLayout $ do
        setTitle (toHtml (categoriaNome categoria))
        $(widgetFile "categorias/detalhe")

getCategoriaEditarR :: CategoriaId -> Handler Html
getCategoriaEditarR categoriaId = do
    categoria <- runDB $ get404 categoriaId
    (formulario, enctype) <- generateFormPost (categoriaForm (Just categoria))
    paginaFormulario "Editar categoria" (CategoriaR categoriaId) formulario enctype

postCategoriaR :: CategoriaId -> Handler Html
postCategoriaR categoriaId = do
    _ <- runDB $ get404 categoriaId
    ((resultado, formulario), enctype) <- runFormPost (categoriaForm Nothing)
    case resultado of
        FormSuccess categoria -> do
            mesmoNome <- runDB $ getBy (UniqueCategoriaNome (categoriaNome categoria))
            case mesmoNome of
                Just (Entity outraId _) | outraId /= categoriaId -> do
                    mensagem "danger" nomeRepetido
                    paginaFormulario "Editar categoria" (CategoriaR categoriaId) formulario enctype
                _ -> do
                    runDB $ replace categoriaId categoria
                    mensagem "success" "Categoria atualizada."
                    redirect (CategoriaR categoriaId)
        _ -> paginaFormulario "Editar categoria" (CategoriaR categoriaId) formulario enctype

postCategoriaExcluirR :: CategoriaId -> Handler Html
postCategoriaExcluirR categoriaId = do
    _ <- runDB $ get404 categoriaId
    livros <- runDB $ count [LivroCategoriaId ==. categoriaId]
    if livros > 0
        then do
            mensagem "danger" ("Não é possível excluir: a categoria tem " <> tshow livros <> " livro(s).")
            redirect (CategoriaR categoriaId)
        else do
            runDB $ delete categoriaId
            mensagem "success" "Categoria excluída."
            redirect CategoriasR
