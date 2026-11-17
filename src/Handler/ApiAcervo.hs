{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiAcervo
    ( postApiLivrosR
    , putApiLivroR
    , deleteApiLivroR
    , postApiLivroImportacaoR
    , postApiLivroExemplaresR
    , putApiExemplarR
    , deleteApiExemplarR
    ) where

import Import
import Api.Validacao
import qualified Data.Text as T
import Integracao.OpenLibrary (buscarPorIsbn)
import Regras.Acervo

lerLivro :: Handler (Livro, [AutorId])
lerLivro = do
    o <- requireCheckJsonBody
    let categoria = campo o "categoriaId" :: Maybe CategoriaId
        editora = campo o "editoraId" :: Maybe EditoraId
        autores = ordNub (fromMaybe [] (campo o "autores")) :: [AutorId]
    (categoriaExiste, editoraExiste, autoresExistentes) <- runDB $ (,,)
        <$> maybe (return False) (fmap isJust . get) categoria
        <*> maybe (return True) (fmap isJust . get) editora
        <*> count [AutorId <-. autores]
    exigirValido $ (,)
        <$> (Livro
            <$> texto "titulo" 200 (campoTexto o "titulo")
            <*> opcional "isbn" "ISBN deve ter 10 ou 13 dígitos." normalizarIsbn (campoTexto o "isbn")
            <*> opcional "ano" "Ano fora do intervalo 1000–2100." (\a -> if a >= 1000 && a <= 2100 then Just a else Nothing) (campo o "ano")
            <*> textoOpcional "sinopse" 4000 (campoTexto o "sinopse")
            <*> opcional "capaUrl" "Informe um endereço http(s) de até 500 caracteres." urlValida (campoTexto o "capaUrl")
            <*> (if editoraExiste then pure editora else falha "editoraId" "Editora não encontrada.")
            <*> maybe (falha "categoriaId" "Escolha uma categoria.")
                    (\c -> if categoriaExiste then pure c else falha "categoriaId" "Categoria não encontrada.") categoria)
        <*> (if autoresExistentes == length autores then pure autores else falha "autores" "Autor não encontrado.")
  where
    opcional nome mensagemErro validar = maybe (pure Nothing) (maybe (falha nome mensagemErro) (pure . Just) . validar)
    urlValida u
        | T.length u <= 500 && ("https://" `T.isPrefixOf` u || "http://" `T.isPrefixOf` u) = Just u
        | otherwise = Nothing

isbnRepetido :: Maybe Text -> Maybe LivroId -> Handler ()
isbnRepetido Nothing _ = return ()
isbnRepetido isbn proprio = do
    existente <- runDB $ getBy (UniqueIsbn isbn)
    when (maybe False ((/= proprio) . Just . entityKey) existente) $ conflito "Já existe um livro com esse ISBN."

postApiLivrosR :: Handler Value
postApiLivrosR = do
    (livro, autores) <- lerLivro
    isbnRepetido (livroIsbn livro) Nothing
    livroId <- runDB $ do
        livroId <- insert livro
        insertMany_ [LivroAutor livroId a | a <- autores]
        return livroId
    sendStatusJSON status201 $ object ["id" .= livroId]

putApiLivroR :: LivroId -> Handler Value
putApiLivroR livroId = do
    _ <- runDB $ get404 livroId
    (livro, autores) <- lerLivro
    isbnRepetido (livroIsbn livro) (Just livroId)
    runDB $ do
        replace livroId livro
        deleteWhere [LivroAutorLivroId ==. livroId]
        insertMany_ [LivroAutor livroId a | a <- autores]
    returnJson $ object ["id" .= livroId]

deleteApiLivroR :: LivroId -> Handler Value
deleteApiLivroR livroId = do
    _ <- runDB $ get404 livroId
    (exemplares, reservas) <- runDB $ (,) <$> count [ExemplarLivroId ==. livroId] <*> count [ReservaLivroId ==. livroId]
    when (exemplares + reservas > 0) $
        conflito ("Não é possível excluir: o livro tem " <> tshow exemplares <> " exemplar(es) e " <> tshow reservas <> " reserva(s).")
    runDB $ delete livroId
    sendResponseStatus status204 ()

postApiLivroImportacaoR :: Handler Value
postApiLivroImportacaoR = do
    o <- requireCheckJsonBody
    let categoria = campo o "categoriaId" :: Maybe CategoriaId
    categoriaExiste <- maybe (return False) (fmap isJust . runDB . get) categoria
    (isbn, categoriaId) <- exigirValido $ (,)
        <$> maybe (falha "isbn" "ISBN deve ter 10 ou 13 dígitos.") pure (campoTexto o "isbn" >>= normalizarIsbn)
        <*> maybe (falha "categoriaId" "Escolha uma categoria.")
                (\c -> if categoriaExiste then pure c else falha "categoriaId" "Categoria não encontrada.") categoria
    isbnRepetido (Just isbn) Nothing
    manager <- getsYesod appHttpManager
    encontrado <- liftIO $ buscarPorIsbn manager isbn
    case encontrado of
        Left erro -> sendStatusJSON status400 $ object ["erro" .= erro, "campos" .= object ["isbn" .= erro]]
        Right externo -> do
            livroId <- runDB $ gravarLivroExterno categoriaId isbn externo
            sendStatusJSON status201 $ object ["id" .= livroId]

lerExemplar :: Handler (Maybe Text, EstadoExemplar)
lerExemplar = do
    o <- requireCheckJsonBody
    exigirValido $ (,)
        <$> maybe (pure Nothing) (fmap Just . texto "codigo" 30 . Just . T.toUpper) (campoTexto o "codigo")
        <*> case campoTexto o "estado" of
            Just "bom" -> pure Bom
            Just "danificado" -> pure Danificado
            Just "perdido" -> pure Perdido
            _ -> falha "estado" "Escolha bom, danificado ou perdido."

codigoRepetido :: Text -> Maybe ExemplarId -> Handler ()
codigoRepetido codigo proprio = do
    existente <- runDB $ getBy (UniqueCodigo codigo)
    when (maybe False ((/= proprio) . Just . entityKey) existente) $ conflito "Já existe um exemplar com esse código."

postApiLivroExemplaresR :: LivroId -> Handler Value
postApiLivroExemplaresR livroId = do
    _ <- runDB $ get404 livroId
    (informado, estado) <- lerExemplar
    codigo <- maybe (runDB (gerarCodigoExemplar livroId)) return informado
    codigoRepetido codigo Nothing
    exemplarId <- runDB $ insert (Exemplar livroId codigo estado True)
    sendStatusJSON status201 $ object ["id" .= exemplarId, "codigo" .= codigo]

putApiExemplarR :: ExemplarId -> Handler Value
putApiExemplarR exemplarId = do
    exemplar <- runDB $ get404 exemplarId
    (informado, estado) <- lerExemplar
    let codigo = fromMaybe (exemplarCodigo exemplar) informado
    codigoRepetido codigo (Just exemplarId)
    runDB $ update exemplarId [ExemplarCodigo =. codigo, ExemplarEstado =. estado]
    returnJson $ object ["id" .= exemplarId, "codigo" .= codigo]

deleteApiExemplarR :: ExemplarId -> Handler Value
deleteApiExemplarR exemplarId = do
    _ <- runDB $ get404 exemplarId
    historico <- runDB $ (+) <$> count [EmprestimoExemplarId ==. exemplarId] <*> count [PedidoExemplarId ==. exemplarId]
    when (historico > 0) $ conflito "Não é possível excluir: o exemplar tem empréstimos ou pedidos registrados. Marque-o como perdido."
    runDB $ delete exemplarId
    sendResponseStatus status204 ()
