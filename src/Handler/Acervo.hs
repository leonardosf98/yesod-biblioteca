{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Acervo
    ( postLivrosR
    , putLivroR
    , deleteLivroR
    , postLivroImportacaoR
    , postLivroExemplaresR
    , putExemplarR
    , deleteExemplarR
    ) where

import Import
import Api.Resposta
import Api.Validacao
import qualified Data.Text as T
import Integracao.OpenLibrary (ErroOpenLibrary (..), buscarPorIsbn)
import Regras.Acervo
import Regras.Pedido (atenderFila)

lerLivro :: Handler (Livro, [AutorId])
lerLivro = do
    o <- requireCheckJsonBody
    let categoria = campo o "categoriaId" :: Maybe CategoriaId
        editora = campo o "editoraId" :: Maybe EditoraId
        autores = ordNub (fromMaybe [] (campo o "autores")) :: [AutorId]
    (categoriaExiste, editoraExiste, autoresEncontrados) <- runDB $ (,,)
        <$> categoriaCadastrada categoria
        <*> maybe (return True) (fmap isJust . get) editora
        <*> count [AutorId <-. autores]
    exigirValido $ (,)
        <$> (Livro
            <$> texto "titulo" 200 (campoTexto o "titulo")
            <*> opcional "isbn" mensagemIsbn normalizarIsbn (campoTexto o "isbn")
            <*> opcional "ano" "Ano fora do intervalo 1000–2100." anoValido (campo o "ano")
            <*> textoOpcional "sinopse" 4000 (campoTexto o "sinopse")
            <*> opcional "capaUrl" "Informe um endereço http(s) de até 500 caracteres." urlValida (campoTexto o "capaUrl")
            <*> (if editoraExiste then pure editora else falha "editoraId" "Editora não encontrada.")
            <*> categoriaValida categoria categoriaExiste)
        <*> (if autoresEncontrados == length autores then pure autores else falha "autores" "Autor não encontrado.")
  where
    anoValido a = if a >= 1000 && a <= 2100 then Just (a :: Int) else Nothing
    urlValida u
        | T.length u <= 500 && ("https://" `T.isPrefixOf` u || "http://" `T.isPrefixOf` u) = Just u
        | otherwise = Nothing

categoriaCadastrada :: MonadIO m => Maybe CategoriaId -> ReaderT SqlBackend m Bool
categoriaCadastrada = maybe (return False) (fmap isJust . get)

categoriaValida :: Maybe CategoriaId -> Bool -> V CategoriaId
categoriaValida Nothing _ = falha "categoriaId" "Escolha uma categoria."
categoriaValida (Just c) True = pure c
categoriaValida (Just _) False = falha "categoriaId" "Categoria não encontrada."

mensagemIsbn :: Text
mensagemIsbn = "ISBN deve ter 10 ou 13 dígitos."

garantirIsbnUnico :: Maybe Text -> Maybe LivroId -> Handler ()
garantirIsbnUnico Nothing _ = return ()
garantirIsbnUnico isbn proprio = garantirUnico (UniqueIsbn isbn) proprio "Já existe um livro com esse ISBN."

postLivrosR :: Handler Value
postLivrosR = do
    (livro, autores) <- lerLivro
    garantirIsbnUnico (livroIsbn livro) Nothing
    livroId <- runDB $ do
        livroId <- insert livro
        insertMany_ [LivroAutor livroId a | a <- autores]
        return livroId
    criado $ object ["id" .= livroId]

putLivroR :: LivroId -> Handler Value
putLivroR livroId = do
    _ <- runDB $ get404 livroId
    (livro, autores) <- lerLivro
    garantirIsbnUnico (livroIsbn livro) (Just livroId)
    runDB $ do
        replace livroId livro
        deleteWhere [LivroAutorLivroId ==. livroId]
        insertMany_ [LivroAutor livroId a | a <- autores]
    returnJson $ object ["id" .= livroId]

deleteLivroR :: LivroId -> Handler Value
deleteLivroR livroId = do
    runDB $ do
        _ <- get404 livroId
        exemplares <- count [ExemplarLivroId ==. livroId]
        reservas <- count [ReservaLivroId ==. livroId]
        when (exemplares + reservas > 0) $ conflito $
            "Não é possível excluir: o livro tem " <> tshow exemplares <> " exemplar(es) e "
                <> tshow reservas <> " reserva(s)."
        delete livroId
    semConteudo

postLivroImportacaoR :: Handler Value
postLivroImportacaoR = do
    o <- requireCheckJsonBody
    let categoria = campo o "categoriaId" :: Maybe CategoriaId
    categoriaExiste <- runDB $ categoriaCadastrada categoria
    (isbn, categoriaId) <- exigirValido $ (,)
        <$> exigido "isbn" mensagemIsbn (campoTexto o "isbn" >>= normalizarIsbn)
        <*> categoriaValida categoria categoriaExiste
    garantirIsbnUnico (Just isbn) Nothing
    manager <- getsYesod appHttpManager
    encontrado <- liftIO $ buscarPorIsbn manager isbn
    case encontrado of
        Left NaoEncontrado -> do
            let erro = "ISBN não encontrado na Open Library." :: Text
            sendStatusJSON status404 $ object ["erro" .= erro, "campos" .= object ["isbn" .= erro]]
        Left (Indisponivel erro) -> recusar status502 erro
        Right externo -> do
            livroId <- runDB $ gravarLivroExterno categoriaId isbn externo
            criado $ object ["id" .= livroId]

lerExemplar :: Handler (Maybe Text, EstadoExemplar)
lerExemplar = do
    o <- requireCheckJsonBody
    exigirValido $ (,)
        <$> textoOpcional "codigo" 30 (T.toUpper <$> campoTexto o "codigo")
        <*> exigido "estado" "Escolha bom, danificado ou perdido." (campoTexto o "estado" >>= estadoDoTexto)

garantirCodigoUnico :: Text -> Maybe ExemplarId -> Handler ()
garantirCodigoUnico codigo proprio = garantirUnico (UniqueCodigo codigo) proprio "Já existe um exemplar com esse código."

postLivroExemplaresR :: LivroId -> Handler Value
postLivroExemplaresR livroId = do
    _ <- runDB $ get404 livroId
    (informado, estado) <- lerExemplar
    codigo <- maybe (runDB (gerarCodigoExemplar livroId)) return informado
    garantirCodigoUnico codigo Nothing
    agora <- liftIO getCurrentTime
    exemplarId <- runDB $ do
        exemplarId <- insert (Exemplar livroId codigo estado True)
        atenderFila livroId agora
        return exemplarId
    criado $ object ["id" .= exemplarId, "codigo" .= codigo]

putExemplarR :: ExemplarId -> Handler Value
putExemplarR exemplarId = do
    exemplar <- runDB $ get404 exemplarId
    (informado, estado) <- lerExemplar
    let codigo = fromMaybe (exemplarCodigo exemplar) informado
    garantirCodigoUnico codigo (Just exemplarId)
    runDB $ update exemplarId [ExemplarCodigo =. codigo, ExemplarEstado =. estado]
    returnJson $ object ["id" .= exemplarId, "codigo" .= codigo]

deleteExemplarR :: ExemplarId -> Handler Value
deleteExemplarR exemplarId = do
    runDB $ do
        _ <- get404 exemplarId
        emprestimos <- count [EmprestimoExemplarId ==. exemplarId]
        pedidos <- count [PedidoExemplarId ==. exemplarId]
        when (emprestimos + pedidos > 0) $ conflito
            "Não é possível excluir: o exemplar tem empréstimos ou pedidos registrados. Marque-o como perdido."
        delete exemplarId
    semConteudo
