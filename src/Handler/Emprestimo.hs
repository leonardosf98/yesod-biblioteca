{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Emprestimo where

import qualified Data.Map.Strict as Map
import Form.Comum
import Import
import Regras.Emprestimo

data Situacao = Abertos | Atrasados | Devolvidos | Todos
    deriving (Eq, Show, Read, Enum, Bounded)

situacoes :: [Situacao]
situacoes = [minBound .. maxBound]

rotuloSituacao :: Situacao -> Text
rotuloSituacao Abertos = "Em aberto"
rotuloSituacao Atrasados = "Atrasados"
rotuloSituacao Devolvidos = "Devolvidos"
rotuloSituacao Todos = "Todos"

filtrosSituacao :: Day -> Situacao -> [Filter Emprestimo]
filtrosSituacao _ Abertos = [EmprestimoDataDevolucao ==. Nothing]
filtrosSituacao dia Atrasados = [EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <. dia]
filtrosSituacao _ Devolvidos = [EmprestimoDataDevolucao !=. Nothing]
filtrosSituacao _ Todos = []

data Contexto = Contexto
    { nomeSocio :: SocioId -> Text
    , descricaoExemplar :: ExemplarId -> Text
    }

carregarContexto :: [Entity Emprestimo] -> Handler Contexto
carregarContexto emprestimos = runDB $ do
    socios <- selectList [SocioId <-. map (emprestimoSocioId . entityVal) emprestimos] []
    exemplares <- selectList [ExemplarId <-. map (emprestimoExemplarId . entityVal) emprestimos] []
    livros <- selectList [LivroId <-. map (exemplarLivroId . entityVal) exemplares] []
    let nomes = Map.fromList [(k, socioNome v) | Entity k v <- socios]
        titulos = Map.fromList [(k, livroTitulo v) | Entity k v <- livros]
        descricoes = Map.fromList
            [ (k, fromMaybe "—" (lookup (exemplarLivroId v) titulos) <> " (" <> exemplarCodigo v <> ")")
            | Entity k v <- exemplares ]
    return Contexto
        { nomeSocio = \k -> fromMaybe "—" (lookup k nomes)
        , descricaoExemplar = \k -> fromMaybe "—" (lookup k descricoes)
        }

emprestimoForm :: [(Text, SocioId)] -> [(Text, ExemplarId)] -> Form (SocioId, ExemplarId)
emprestimoForm socios exemplares = renderizar $ (,)
    <$> areq (selectField (porChave socios)) "Sócio" Nothing
    <*> areq (selectField (porChave exemplares)) "Exemplar" Nothing
  where
    porChave pares = return $ mkOptionList
        [Option rotulo chave (toPathPiece chave) | (rotulo, chave) <- pares]

opcoesEmprestimo :: Handler ([(Text, SocioId)], [(Text, ExemplarId)])
opcoesEmprestimo = runDB $ do
    socios <- selectList [] [Asc SocioNome]
    exemplares <- selectList [ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido] [Asc ExemplarCodigo]
    livros <- selectList [LivroId <-. map (exemplarLivroId . entityVal) exemplares] []
    let titulos = Map.fromList [(k, livroTitulo v) | Entity k v <- livros]
        rotulo e = exemplarCodigo e <> " — " <> fromMaybe "" (lookup (exemplarLivroId e) titulos)
    return
        ( [(socioNome v <> " <" <> socioEmail v <> ">", k) | Entity k v <- socios]
        , [(rotulo v, k) | Entity k v <- exemplares]
        )

getEmprestimosR :: Handler Html
getEmprestimosR = do
    dia <- hoje
    situacao <- fromMaybe Abertos . (>>= readMay) <$> lookupGetParam "situacao"
    emprestimos <- runDB $ selectList (filtrosSituacao dia situacao) [Desc EmprestimoDataEmprestimo]
    contexto <- carregarContexto emprestimos
    let atrasado e = isNothing (emprestimoDataDevolucao e) && emprestimoDataPrevista e < dia
    defaultLayout $ do
        setTitle "Empréstimos"
        $(widgetFile "emprestimos/lista")

getEmprestimoNovoR :: Handler Html
getEmprestimoNovoR = do
    (socios, exemplares) <- opcoesEmprestimo
    (formulario, enctype) <- generateFormPost (emprestimoForm socios exemplares)
    paginaFormulario "Novo empréstimo" EmprestimosR formulario enctype

postEmprestimosR :: Handler Html
postEmprestimosR = do
    (socios, exemplares) <- opcoesEmprestimo
    ((resultado, formulario), enctype) <- runFormPost (emprestimoForm socios exemplares)
    let reexibir = paginaFormulario "Novo empréstimo" EmprestimosR formulario enctype
    case resultado of
        FormSuccess (socioId, exemplarId) -> do
            dia <- hoje
            criado <- runDB $ realizarEmprestimo socioId exemplarId dia
            case criado of
                Left erro -> mensagem "danger" erro >> reexibir
                Right emprestimoId -> do
                    mensagem "success" "Empréstimo registrado."
                    redirect (EmprestimoR emprestimoId)
        _ -> reexibir

getEmprestimoR :: EmprestimoId -> Handler Html
getEmprestimoR emprestimoId = do
    emprestimo <- runDB $ get404 emprestimoId
    contexto <- carregarContexto [Entity emprestimoId emprestimo]
    dia <- hoje
    let aberto = isNothing (emprestimoDataDevolucao emprestimo)
        multaPrevista = calcularMulta (emprestimoDataPrevista emprestimo) dia
    token <- reqToken <$> getRequest
    defaultLayout $ do
        setTitle "Empréstimo"
        $(widgetFile "emprestimos/detalhe")

prorrogarForm :: Emprestimo -> Form Day
prorrogarForm emprestimo = renderizar $
    areq (checkBool (>= emprestimoDataEmprestimo emprestimo) ("A data não pode ser anterior ao empréstimo" :: Text) dayField)
        "Devolver até" (Just (emprestimoDataPrevista emprestimo))

exigirAberto :: EmprestimoId -> Handler Emprestimo
exigirAberto emprestimoId = do
    emprestimo <- runDB $ get404 emprestimoId
    when (isJust (emprestimoDataDevolucao emprestimo)) $ do
        mensagem "warning" "Esse empréstimo já foi devolvido."
        redirect (EmprestimoR emprestimoId)
    return emprestimo

getEmprestimoEditarR :: EmprestimoId -> Handler Html
getEmprestimoEditarR emprestimoId = do
    emprestimo <- exigirAberto emprestimoId
    (formulario, enctype) <- generateFormPost (prorrogarForm emprestimo)
    paginaFormulario "Prorrogar empréstimo" (EmprestimoR emprestimoId) formulario enctype

postEmprestimoR :: EmprestimoId -> Handler Html
postEmprestimoR emprestimoId = do
    emprestimo <- exigirAberto emprestimoId
    ((resultado, formulario), enctype) <- runFormPost (prorrogarForm emprestimo)
    case resultado of
        FormSuccess prevista -> do
            runDB $ update emprestimoId [EmprestimoDataPrevista =. prevista]
            mensagem "success" "Prazo atualizado."
            redirect (EmprestimoR emprestimoId)
        _ -> paginaFormulario "Prorrogar empréstimo" (EmprestimoR emprestimoId) formulario enctype

postEmprestimoDevolverR :: EmprestimoId -> Handler Html
postEmprestimoDevolverR emprestimoId = do
    dia <- hoje
    devolvido <- runDB $ registrarDevolucao emprestimoId dia
    case devolvido of
        Left erro -> mensagem "danger" erro
        Right 0 -> mensagem "success" "Devolução registrada, sem multa."
        Right multa -> mensagem "warning" ("Devolução registrada com atraso. Multa: " <> formatarCentavos multa <> ".")
    redirect (EmprestimoR emprestimoId)

postEmprestimoExcluirR :: EmprestimoId -> Handler Html
postEmprestimoExcluirR emprestimoId = do
    cancelado <- runDB $ cancelarEmprestimo emprestimoId
    case cancelado of
        Left erro -> mensagem "danger" erro >> redirect (EmprestimoR emprestimoId)
        Right () -> mensagem "success" "Empréstimo excluído e exemplar liberado." >> redirect EmprestimosR
