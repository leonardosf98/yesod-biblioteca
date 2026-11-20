{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Cadastros
    ( getAutoresR, postAutoresR, putAutorR, deleteAutorR
    , getEditorasR, postEditorasR, putEditoraR, deleteEditoraR
    , getCategoriasR, postCategoriasR, putCategoriaR, deleteCategoriaR
    ) where

import Import
import Api.Relacionados (contarPorChave)
import Api.Resposta
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

excluirSemLivros :: PersistRecordBackend r SqlBackend => Key r -> Int -> Text -> Handler Value
excluirSemLivros chave livros mensagem = do
    when (livros > 0) $ conflito ("Não é possível excluir: " <> mensagem)
    runDB $ delete chave
    semConteudo

getAutoresR :: Handler Value
getAutoresR = do
    (autores, vinculos) <- runDB $ (,) <$> selectList [] [Asc AutorNome] <*> selectList [] []
    let livros = contarPorChave (map (livroAutorAutorId . entityVal) vinculos)
    returnJson $ object ["autores" .= map (autorJson livros) autores]

postAutoresR :: Handler Value
postAutoresR = do
    autor <- lerAutor
    autorId <- runDB $ insert autor
    criado (autorJson mempty (Entity autorId autor))

putAutorR :: AutorId -> Handler Value
putAutorR autorId = do
    _ <- runDB $ get404 autorId
    autor <- lerAutor
    runDB $ replace autorId autor
    returnJson (autorJson mempty (Entity autorId autor))

deleteAutorR :: AutorId -> Handler Value
deleteAutorR autorId = do
    livros <- runDB $ get404 autorId >> count [LivroAutorAutorId ==. autorId]
    excluirSemLivros autorId livros ("o autor está ligado a " <> tshow livros <> " livro(s).")

getEditorasR :: Handler Value
getEditorasR = do
    (editoras, livros) <- runDB $ (,) <$> selectList [] [Asc EditoraNome] <*> selectList [LivroEditoraId !=. Nothing] []
    let porEditora = contarPorChave (mapMaybe (livroEditoraId . entityVal) livros)
    returnJson $ object ["editoras" .= map (editoraJson porEditora) editoras]

garantirEditoraUnica :: Text -> Maybe EditoraId -> Handler ()
garantirEditoraUnica nome proprio = garantirUnico (UniqueEditoraNome nome) proprio "Já existe uma editora com esse nome."

postEditorasR :: Handler Value
postEditorasR = do
    editora <- lerEditora
    garantirEditoraUnica (editoraNome editora) Nothing
    editoraId <- runDB $ insert editora
    criado (editoraJson mempty (Entity editoraId editora))

putEditoraR :: EditoraId -> Handler Value
putEditoraR editoraId = do
    _ <- runDB $ get404 editoraId
    editora <- lerEditora
    garantirEditoraUnica (editoraNome editora) (Just editoraId)
    runDB $ replace editoraId editora
    returnJson (editoraJson mempty (Entity editoraId editora))

deleteEditoraR :: EditoraId -> Handler Value
deleteEditoraR editoraId = do
    livros <- runDB $ get404 editoraId >> count [LivroEditoraId ==. Just editoraId]
    excluirSemLivros editoraId livros ("a editora tem " <> tshow livros <> " livro(s) no acervo.")

getCategoriasR :: Handler Value
getCategoriasR = do
    (categorias, livros) <- runDB $ (,) <$> selectList [] [Asc CategoriaNome] <*> selectList [] []
    let porCategoria = contarPorChave (map (livroCategoriaId . entityVal) livros)
    returnJson $ object ["categorias" .= map (categoriaJson porCategoria) categorias]

garantirCategoriaUnica :: Text -> Maybe CategoriaId -> Handler ()
garantirCategoriaUnica nome proprio = garantirUnico (UniqueCategoriaNome nome) proprio "Já existe uma categoria com esse nome."

postCategoriasR :: Handler Value
postCategoriasR = do
    categoria <- lerCategoria
    garantirCategoriaUnica (categoriaNome categoria) Nothing
    categoriaId <- runDB $ insert categoria
    criado (categoriaJson mempty (Entity categoriaId categoria))

putCategoriaR :: CategoriaId -> Handler Value
putCategoriaR categoriaId = do
    _ <- runDB $ get404 categoriaId
    categoria <- lerCategoria
    garantirCategoriaUnica (categoriaNome categoria) (Just categoriaId)
    runDB $ replace categoriaId categoria
    returnJson (categoriaJson mempty (Entity categoriaId categoria))

deleteCategoriaR :: CategoriaId -> Handler Value
deleteCategoriaR categoriaId = do
    livros <- runDB $ get404 categoriaId >> count [LivroCategoriaId ==. categoriaId]
    excluirSemLivros categoriaId livros ("a categoria tem " <> tshow livros <> " livro(s).")
