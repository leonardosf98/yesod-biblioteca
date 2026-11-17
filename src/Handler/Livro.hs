{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Livro where

import Control.Monad (mfilter)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Form.Comum
import Import
import Regras.Acervo (normalizarIsbn)
import Filtro (contem)

livroForm :: Maybe (Livro, [AutorId]) -> Form (Livro, [AutorId])
livroForm atual = renderizar $ (,)
    <$> (Livro
        <$> areq (textoLimitado 200) "Título" (livroTitulo <$> livro)
        <*> aopt isbnField "ISBN" (livroIsbn <$> livro)
        <*> aopt anoField "Ano" (livroAno <$> livro)
        <*> (fmap unTextarea <$> aopt textareaField "Sinopse" (fmap Textarea . livroSinopse <$> livro))
        <*> aopt urlField "URL da capa" (livroCapaUrl <$> livro)
        <*> aopt (selectField editoras) "Editora" (livroEditoraId <$> livro)
        <*> areq (selectField categorias) "Categoria" (livroCategoriaId <$> livro))
    <*> (fromMaybe [] <$> aopt (multiSelectField autores) "Autores" (Just . snd <$> atual))
  where
    livro = fst <$> atual
    editoras = optionsPersistKey [] [Asc EditoraNome] editoraNome
    categorias = optionsPersistKey [] [Asc CategoriaNome] categoriaNome
    autores = optionsPersistKey [] [Asc AutorNome] autorNome

isbnField :: Field Handler Text
isbnField = checkM (return . maybe (Left ("ISBN deve ter 10 ou 13 dígitos" :: Text)) Right . normalizarIsbn) textField

anoField :: Field Handler Int
anoField = checkBool (\ano -> ano >= 1000 && ano <= 2100) ("Ano fora do intervalo 1000–2100" :: Text) intField

isbnEmUso :: Maybe Text -> Maybe LivroId -> Handler Bool
isbnEmUso Nothing _ = return False
isbnEmUso (Just isbn) proprio = do
    existente <- runDB $ getBy (UniqueIsbn (Just isbn))
    return $ case existente of
        Just (Entity outroId _) -> Just outroId /= proprio
        Nothing -> False

isbnRepetido :: Text
isbnRepetido = "Já existe um livro com esse ISBN."

getLivrosR :: Handler Html
getLivrosR = do
    busca <- fmap T.strip <$> lookupGetParam "busca"
    categoriaFiltro <- (>>= fromPathPiece) <$> lookupGetParam "categoria"
    let filtros = catMaybes
            [ contem LivroTitulo <$> mfilter (not . null) busca
            , (LivroCategoriaId ==.) <$> categoriaFiltro
            ]
    (livros, categorias, editoras) <- runDB $ (,,)
        <$> selectList filtros [Asc LivroTitulo]
        <*> selectList [] [Asc CategoriaNome]
        <*> selectList [] []
    let nomeCategoria = Map.fromList [(k, categoriaNome v) | Entity k v <- categorias]
        nomeEditora = Map.fromList [(k, editoraNome v) | Entity k v <- editoras]
    defaultLayout $ do
        setTitle "Livros"
        $(widgetFile "livros/lista")


getLivroNovoR :: Handler Html
getLivroNovoR = do
    (formulario, enctype) <- generateFormPost (livroForm Nothing)
    paginaFormulario "Novo livro" LivrosR formulario enctype

postLivrosR :: Handler Html
postLivrosR = do
    ((resultado, formulario), enctype) <- runFormPost (livroForm Nothing)
    case resultado of
        FormSuccess (livro, autores) -> do
            repetido <- isbnEmUso (livroIsbn livro) Nothing
            if repetido
                then do
                    mensagem "danger" isbnRepetido
                    paginaFormulario "Novo livro" LivrosR formulario enctype
                else do
                    livroId <- runDB $ do
                        livroId <- insert livro
                        insertMany_ [LivroAutor livroId autorId | autorId <- autores]
                        return livroId
                    mensagem "success" "Livro cadastrado."
                    redirect (LivroR livroId)
        _ -> paginaFormulario "Novo livro" LivrosR formulario enctype

getLivroR :: LivroId -> Handler Html
getLivroR livroId = do
    (livro, autores, editora, categoria, exemplares) <- runDB $ do
        livro <- get404 livroId
        vinculos <- selectList [LivroAutorLivroId ==. livroId] []
        autores <- selectList [AutorId <-. map (livroAutorAutorId . entityVal) vinculos] [Asc AutorNome]
        editora <- maybe (return Nothing) get (livroEditoraId livro)
        categoria <- getJust (livroCategoriaId livro)
        exemplares <- selectList [ExemplarLivroId ==. livroId] [Asc ExemplarCodigo]
        return (livro, autores, editora, categoria, exemplares)
    defaultLayout $ do
        setTitle (toHtml (livroTitulo livro))
        $(widgetFile "livros/detalhe")

getLivroEditarR :: LivroId -> Handler Html
getLivroEditarR livroId = do
    (livro, autores) <- runDB $ (,)
        <$> get404 livroId
        <*> selectList [LivroAutorLivroId ==. livroId] []
    let atual = (livro, map (livroAutorAutorId . entityVal) autores)
    (formulario, enctype) <- generateFormPost (livroForm (Just atual))
    paginaFormulario "Editar livro" (LivroR livroId) formulario enctype

postLivroR :: LivroId -> Handler Html
postLivroR livroId = do
    _ <- runDB $ get404 livroId
    ((resultado, formulario), enctype) <- runFormPost (livroForm Nothing)
    case resultado of
        FormSuccess (livro, autores) -> do
            repetido <- isbnEmUso (livroIsbn livro) (Just livroId)
            if repetido
                then do
                    mensagem "danger" isbnRepetido
                    paginaFormulario "Editar livro" (LivroR livroId) formulario enctype
                else do
                    runDB $ do
                        replace livroId livro
                        deleteWhere [LivroAutorLivroId ==. livroId]
                        insertMany_ [LivroAutor livroId autorId | autorId <- autores]
                    mensagem "success" "Livro atualizado."
                    redirect (LivroR livroId)
        _ -> paginaFormulario "Editar livro" (LivroR livroId) formulario enctype

postLivroExcluirR :: LivroId -> Handler Html
postLivroExcluirR livroId = do
    _ <- runDB $ get404 livroId
    (exemplares, reservas) <- runDB $ (,)
        <$> count [ExemplarLivroId ==. livroId]
        <*> count [ReservaLivroId ==. livroId]
    if exemplares > 0 || reservas > 0
        then do
            mensagem "danger" ("Não é possível excluir: o livro tem " <> tshow exemplares <> " exemplar(es) e " <> tshow reservas <> " reserva(s).")
            redirect (LivroR livroId)
        else do
            runDB $ delete livroId
            mensagem "success" "Livro excluído."
            redirect LivrosR
