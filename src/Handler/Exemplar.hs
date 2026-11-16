{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Handler.Exemplar where

import Database.Persist.Sql (fromSqlKey)
import Form.Comum
import Import

exemplarForm :: Maybe Exemplar -> Form (Maybe Text, EstadoExemplar)
exemplarForm atual = renderizar $ (,)
    <$> aopt (textoLimitado 30) codigo (Just . exemplarCodigo <$> atual)
    <*> areq (selectField optionsEnum) "Estado" (exemplarEstado <$> atual)
  where
    codigo = "Código (em branco para gerar)"

codigoRepetido :: Text
codigoRepetido = "Já existe um exemplar com esse código."

gerarCodigo :: LivroId -> Handler Text
gerarCodigo livroId = runDB $ do
    existentes <- count [ExemplarLivroId ==. livroId]
    let candidatos = [prefixo <> tshow n | n <- [existentes + 1 ..]]
    livres <- filterM (fmap isNothing . getBy . UniqueCodigo) (take 50 candidatos)
    maybe (error "sem código livre") return (headMay livres)
  where
    prefixo = "L" <> tshow (fromSqlKey livroId) <> "-"

codigoEmUso :: Text -> Maybe ExemplarId -> Handler Bool
codigoEmUso codigo proprio = do
    existente <- runDB $ getBy (UniqueCodigo codigo)
    return $ case existente of
        Just (Entity outroId _) -> Just outroId /= proprio
        Nothing -> False

getExemplarNovoR :: LivroId -> Handler Html
getExemplarNovoR livroId = do
    _ <- runDB $ get404 livroId
    (formulario, enctype) <- generateFormPost (exemplarForm Nothing)
    paginaFormulario "Novo exemplar" (ExemplaresR livroId) formulario enctype

postExemplaresR :: LivroId -> Handler Html
postExemplaresR livroId = do
    _ <- runDB $ get404 livroId
    ((resultado, formulario), enctype) <- runFormPost (exemplarForm Nothing)
    case resultado of
        FormSuccess (informado, estado) -> do
            codigo <- maybe (gerarCodigo livroId) return informado
            repetido <- codigoEmUso codigo Nothing
            if repetido
                then do
                    mensagem "danger" codigoRepetido
                    paginaFormulario "Novo exemplar" (ExemplaresR livroId) formulario enctype
                else do
                    runDB $ insert_ (Exemplar livroId codigo estado True)
                    mensagem "success" ("Exemplar " <> codigo <> " cadastrado.")
                    redirect (LivroR livroId)
        _ -> paginaFormulario "Novo exemplar" (ExemplaresR livroId) formulario enctype

getExemplarEditarR :: ExemplarId -> Handler Html
getExemplarEditarR exemplarId = do
    exemplar <- runDB $ get404 exemplarId
    (formulario, enctype) <- generateFormPost (exemplarForm (Just exemplar))
    defaultLayout $ do
        setTitle "Editar exemplar"
        [whamlet|
<h1>Exemplar #{exemplarCodigo exemplar}
<form .form-principal method=post action=@{ExemplarR exemplarId} enctype=#{enctype}>
    ^{formulario}
    <button .btn .btn-primary type=submit>Salvar
<div .acoes>
    ^{botaoExcluir (ExemplarExcluirR exemplarId)}
|]

postExemplarR :: ExemplarId -> Handler Html
postExemplarR exemplarId = do
    exemplar <- runDB $ get404 exemplarId
    ((resultado, formulario), enctype) <- runFormPost (exemplarForm Nothing)
    case resultado of
        FormSuccess (informado, estado) -> do
            let codigo = fromMaybe (exemplarCodigo exemplar) informado
            repetido <- codigoEmUso codigo (Just exemplarId)
            if repetido
                then do
                    mensagem "danger" codigoRepetido
                    paginaFormulario "Editar exemplar" (ExemplarR exemplarId) formulario enctype
                else do
                    runDB $ update exemplarId [ExemplarCodigo =. codigo, ExemplarEstado =. estado]
                    mensagem "success" "Exemplar atualizado."
                    redirect (LivroR (exemplarLivroId exemplar))
        _ -> paginaFormulario "Editar exemplar" (ExemplarR exemplarId) formulario enctype

postExemplarExcluirR :: ExemplarId -> Handler Html
postExemplarExcluirR exemplarId = do
    exemplar <- runDB $ get404 exemplarId
    emprestimos <- runDB $ count [EmprestimoExemplarId ==. exemplarId]
    if emprestimos > 0
        then do
            mensagem "danger" "Não é possível excluir: o exemplar tem empréstimos registrados. Marque-o como Perdido."
            redirect (ExemplarEditarR exemplarId)
        else do
            runDB $ delete exemplarId
            mensagem "success" "Exemplar excluído."
            redirect (LivroR (exemplarLivroId exemplar))
