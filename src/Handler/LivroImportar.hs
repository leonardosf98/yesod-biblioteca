{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.LivroImportar where

import Form.Comum
import Handler.Livro (isbnField, isbnEmUso)
import Import
import Integracao.OpenLibrary

importarForm :: Form (Text, CategoriaId)
importarForm = renderizar $ (,)
    <$> areq isbnField "ISBN" Nothing
    <*> areq (selectField categorias) "Categoria" Nothing
  where
    categorias = optionsPersistKey [] [Asc CategoriaNome] categoriaNome

getLivroImportarR :: Handler Html
getLivroImportarR = do
    (formulario, enctype) <- generateFormPost importarForm
    paginaFormulario "Importar por ISBN" LivroImportarR formulario enctype

postLivroImportarR :: Handler Html
postLivroImportarR = do
    ((resultado, formulario), enctype) <- runFormPost importarForm
    let reexibir texto = do
            mensagem "danger" texto
            paginaFormulario "Importar por ISBN" LivroImportarR formulario enctype
    case resultado of
        FormSuccess (isbn, categoriaId) -> do
            repetido <- isbnEmUso (Just isbn) Nothing
            if repetido
                then reexibir "Esse ISBN já está no acervo."
                else do
                    manager <- getsYesod appHttpManager
                    encontrado <- liftIO $ buscarPorIsbn manager isbn
                    case encontrado of
                        Left erro -> reexibir erro
                        Right externo -> do
                            livroId <- runDB $ gravarLivroExterno categoriaId isbn externo
                            mensagem "success" "Livro importado da Open Library."
                            redirect (LivroR livroId)
        _ -> paginaFormulario "Importar por ISBN" LivroImportarR formulario enctype

gravarLivroExterno :: MonadIO m => CategoriaId -> Text -> LivroExterno -> ReaderT SqlBackend m LivroId
gravarLivroExterno categoriaId isbn externo = do
    editoraId <- forM (externoEditora externo) $ \nome ->
        either entityKey id <$> insertBy (Editora nome Nothing)
    autores <- forM (externoAutores externo) $ \nome -> do
        existente <- selectFirst [AutorNome ==. nome] []
        maybe (insert (Autor nome Nothing)) (return . entityKey) existente
    livroId <- insert Livro
        { livroTitulo = externoTitulo externo
        , livroIsbn = Just isbn
        , livroAno = externoAno externo
        , livroSinopse = externoSinopse externo
        , livroCapaUrl = externoCapa externo
        , livroEditoraId = editoraId
        , livroCategoriaId = categoriaId
        }
    insertMany_ [LivroAutor livroId autorId | autorId <- ordNub autores]
    return livroId
