{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiCadastros
    ( getApiAutoresR, postApiAutoresR, putApiAutorR, deleteApiAutorR
    , getApiEditorasR, postApiEditorasR, putApiEditoraR, deleteApiEditoraR
    , getApiCategoriasR, postApiCategoriasR, putApiCategoriaR, deleteApiCategoriaR
    ) where

import Import
import Api.Validacao
import qualified Data.Map.Strict as Map

lerAutor :: Handler Autor
lerAutor = do
    o <- requireCheckJsonBody
    exigirValido $ Autor
        <$> texto "nome" 120 (campoTexto o "nome")
        <*> textoOpcional "nacionalidade" 60 (campoTexto o "nacionalidade")

lerEditora :: Handler Editora
lerEditora = do
    o <- requireCheckJsonBody
    exigirValido $ Editora
        <$> texto "nome" 120 (campoTexto o "nome")
        <*> textoOpcional "cidade" 80 (campoTexto o "cidade")

lerCategoria :: Handler Categoria
lerCategoria = do
    o <- requireCheckJsonBody
    exigirValido $ Categoria
        <$> texto "nome" 60 (campoTexto o "nome")
        <*> textoOpcional "descricao" 500 (campoTexto o "descricao")

autorJson :: Map AutorId Int -> Entity Autor -> Value
autorJson livros (Entity k a) = object
    ["id" .= k, "nome" .= autorNome a, "nacionalidade" .= autorNacionalidade a, "livros" .= Map.findWithDefault 0 k livros]

editoraJson :: Map EditoraId Int -> Entity Editora -> Value
editoraJson livros (Entity k e) = object
    ["id" .= k, "nome" .= editoraNome e, "cidade" .= editoraCidade e, "livros" .= Map.findWithDefault 0 k livros]

categoriaJson :: Map CategoriaId Int -> Entity Categoria -> Value
categoriaJson livros (Entity k c) = object
    ["id" .= k, "nome" .= categoriaNome c, "descricao" .= categoriaDescricao c, "livros" .= Map.findWithDefault 0 k livros]

contar :: Ord k => [k] -> Map k Int
contar chaves = Map.fromListWith (+) [(k, 1) | k <- chaves]

criado :: ToJSON v => v -> Handler Value
criado = sendStatusJSON status201

semConteudo :: Handler Value
semConteudo = sendResponseStatus status204 ()

getApiAutoresR :: Handler Value
getApiAutoresR = do
    (autores, vinculos) <- runDB $ (,) <$> selectList [] [Asc AutorNome] <*> selectList [] []
    let livros = contar (map (livroAutorAutorId . entityVal) vinculos)
    returnJson $ object ["autores" .= map (autorJson livros) autores]

postApiAutoresR :: Handler Value
postApiAutoresR = do
    autor <- lerAutor
    autorId <- runDB $ insert autor
    criado (autorJson mempty (Entity autorId autor))

putApiAutorR :: AutorId -> Handler Value
putApiAutorR autorId = do
    _ <- runDB $ get404 autorId
    autor <- lerAutor
    runDB $ replace autorId autor
    returnJson (autorJson mempty (Entity autorId autor))

deleteApiAutorR :: AutorId -> Handler Value
deleteApiAutorR autorId = do
    _ <- runDB $ get404 autorId
    livros <- runDB $ count [LivroAutorAutorId ==. autorId]
    when (livros > 0) $ conflito ("Não é possível excluir: o autor está ligado a " <> tshow livros <> " livro(s).")
    runDB $ delete autorId
    semConteudo

getApiEditorasR :: Handler Value
getApiEditorasR = do
    (editoras, livros) <- runDB $ (,) <$> selectList [] [Asc EditoraNome] <*> selectList [LivroEditoraId !=. Nothing] []
    let porEditora = contar (mapMaybe (livroEditoraId . entityVal) livros)
    returnJson $ object ["editoras" .= map (editoraJson porEditora) editoras]

editoraRepetida :: Text -> Maybe EditoraId -> Handler ()
editoraRepetida nome proprio = do
    existente <- runDB $ getBy (UniqueEditoraNome nome)
    when (maybe False ((/= proprio) . Just . entityKey) existente) $ conflito "Já existe uma editora com esse nome."

postApiEditorasR :: Handler Value
postApiEditorasR = do
    editora <- lerEditora
    editoraRepetida (editoraNome editora) Nothing
    editoraId <- runDB $ insert editora
    criado (editoraJson mempty (Entity editoraId editora))

putApiEditoraR :: EditoraId -> Handler Value
putApiEditoraR editoraId = do
    _ <- runDB $ get404 editoraId
    editora <- lerEditora
    editoraRepetida (editoraNome editora) (Just editoraId)
    runDB $ replace editoraId editora
    returnJson (editoraJson mempty (Entity editoraId editora))

deleteApiEditoraR :: EditoraId -> Handler Value
deleteApiEditoraR editoraId = do
    _ <- runDB $ get404 editoraId
    livros <- runDB $ count [LivroEditoraId ==. Just editoraId]
    when (livros > 0) $ conflito ("Não é possível excluir: a editora tem " <> tshow livros <> " livro(s) no acervo.")
    runDB $ delete editoraId
    semConteudo

getApiCategoriasR :: Handler Value
getApiCategoriasR = do
    (categorias, livros) <- runDB $ (,) <$> selectList [] [Asc CategoriaNome] <*> selectList [] []
    let porCategoria = contar (map (livroCategoriaId . entityVal) livros)
    returnJson $ object ["categorias" .= map (categoriaJson porCategoria) categorias]

categoriaRepetida :: Text -> Maybe CategoriaId -> Handler ()
categoriaRepetida nome proprio = do
    existente <- runDB $ getBy (UniqueCategoriaNome nome)
    when (maybe False ((/= proprio) . Just . entityKey) existente) $ conflito "Já existe uma categoria com esse nome."

postApiCategoriasR :: Handler Value
postApiCategoriasR = do
    categoria <- lerCategoria
    categoriaRepetida (categoriaNome categoria) Nothing
    categoriaId <- runDB $ insert categoria
    criado (categoriaJson mempty (Entity categoriaId categoria))

putApiCategoriaR :: CategoriaId -> Handler Value
putApiCategoriaR categoriaId = do
    _ <- runDB $ get404 categoriaId
    categoria <- lerCategoria
    categoriaRepetida (categoriaNome categoria) (Just categoriaId)
    runDB $ replace categoriaId categoria
    returnJson (categoriaJson mempty (Entity categoriaId categoria))

deleteApiCategoriaR :: CategoriaId -> Handler Value
deleteApiCategoriaR categoriaId = do
    _ <- runDB $ get404 categoriaId
    livros <- runDB $ count [LivroCategoriaId ==. categoriaId]
    when (livros > 0) $ conflito ("Não é possível excluir: a categoria tem " <> tshow livros <> " livro(s).")
    runDB $ delete categoriaId
    semConteudo
