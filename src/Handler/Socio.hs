{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Socio where

import Data.Char (isDigit)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Form.Comum
import Import
import Integracao.ViaCep

data DadosSocio = DadosSocio
    { dadosNome :: Text
    , dadosEmail :: Text
    , dadosTelefone :: Maybe Text
    , dadosCep :: Maybe Text
    , dadosNumero :: Maybe Text
    }

socioForm :: Maybe Socio -> Form DadosSocio
socioForm atual = renderizar $ DadosSocio
    <$> areq (textoLimitado 120) "Nome" (socioNome <$> atual)
    <*> (T.toLower <$> areq emailField "E-mail" (socioEmail <$> atual))
    <*> aopt (digitos [10, 11] "Telefone deve ter DDD + 8 ou 9 dígitos") "Telefone" (socioTelefone <$> atual)
    <*> aopt (digitos [8] "CEP deve ter 8 dígitos") "CEP" (socioCep <$> atual)
    <*> aopt (textoLimitado 10) "Número" (socioNumero <$> atual)

digitos :: [Int] -> Text -> Field Handler Text
digitos tamanhos erro = check validar textField
  where
    validar texto
        | T.length limpo `elem` tamanhos && T.all isDigit limpo = Right limpo
        | otherwise = Left erro
      where
        limpo = T.filter (`notElem` (" -()." :: String)) texto

paraSocio :: DadosSocio -> Socio
paraSocio dados = Socio
    { socioNome = dadosNome dados
    , socioEmail = dadosEmail dados
    , socioTelefone = dadosTelefone dados
    , socioCep = dadosCep dados
    , socioLogradouro = Nothing
    , socioNumero = dadosNumero dados
    , socioBairro = Nothing
    , socioCidade = Nothing
    , socioUf = Nothing
    }

resolverEndereco :: Maybe Socio -> DadosSocio -> Handler (Either Text Socio)
resolverEndereco anterior dados = case dadosCep dados of
    Nothing -> return (Right base)
    Just cep
        | Just cep == (anterior >>= socioCep) -> return (Right (manterEndereco anterior))
        | otherwise -> do
            manager <- getsYesod appHttpManager
            fmap comEndereco <$> liftIO (buscarCep manager cep)
  where
    base = paraSocio dados
    manterEndereco socio = base
        { socioLogradouro = socio >>= socioLogradouro
        , socioBairro = socio >>= socioBairro
        , socioCidade = socio >>= socioCidade
        , socioUf = socio >>= socioUf
        }
    comEndereco endereco = base
        { socioLogradouro = enderecoLogradouro endereco
        , socioBairro = enderecoBairro endereco
        , socioCidade = Just (enderecoCidade endereco)
        , socioUf = Just (enderecoUf endereco)
        }

emailEmUso :: Text -> Maybe SocioId -> Handler Bool
emailEmUso email proprio = do
    existente <- runDB $ getBy (UniqueSocioEmail email)
    return $ case existente of
        Just (Entity outroId _) -> Just outroId /= proprio
        Nothing -> False

emailRepetido :: Text
emailRepetido = "Já existe um sócio com esse e-mail."

getSociosR :: Handler Html
getSociosR = do
    socios <- runDB $ selectList [] [Asc SocioNome]
    defaultLayout $ do
        setTitle "Sócios"
        $(widgetFile "socios/lista")

getSocioNovoR :: Handler Html
getSocioNovoR = do
    (formulario, enctype) <- generateFormPost (socioForm Nothing)
    paginaFormulario "Novo sócio" SociosR formulario enctype

postSociosR :: Handler Html
postSociosR = do
    ((resultado, formulario), enctype) <- runFormPost (socioForm Nothing)
    let reexibir = paginaFormulario "Novo sócio" SociosR formulario enctype
    case resultado of
        FormSuccess dados -> do
            repetido <- emailEmUso (dadosEmail dados) Nothing
            if repetido
                then mensagem "danger" emailRepetido >> reexibir
                else do
                    resolvido <- resolverEndereco Nothing dados
                    case resolvido of
                        Left erro -> mensagem "danger" erro >> reexibir
                        Right socio -> do
                            socioId <- runDB $ insert socio
                            mensagem "success" "Sócio cadastrado."
                            redirect (SocioR socioId)
        _ -> reexibir

getSocioR :: SocioId -> Handler Html
getSocioR socioId = do
    (socio, emprestimos, reservas, titulos, codigos) <- runDB $ do
        socio <- get404 socioId
        emprestimos <- selectList [EmprestimoSocioId ==. socioId] [Desc EmprestimoDataEmprestimo]
        reservas <- selectList [ReservaSocioId ==. socioId] [Desc ReservaDataReserva]
        exemplares <- selectList [ExemplarId <-. map (emprestimoExemplarId . entityVal) emprestimos] []
        let livrosIds = map (exemplarLivroId . entityVal) exemplares ++ map (reservaLivroId . entityVal) reservas
        livros <- selectList [LivroId <-. livrosIds] []
        let titulos = Map.fromList [(k, livroTitulo v) | Entity k v <- livros]
            codigos = Map.fromList [(k, (exemplarCodigo v, exemplarLivroId v)) | Entity k v <- exemplares]
        return (socio, emprestimos, reservas, titulos, codigos)
    let tituloDoExemplar exemplarId = fromMaybe "—" $ do
            (_, livroId) <- lookup exemplarId codigos
            lookup livroId titulos
        codigoDoExemplar exemplarId = maybe "—" fst (lookup exemplarId codigos)
        tituloDoLivro livroId = fromMaybe "—" (lookup livroId titulos)
    token <- reqToken <$> getRequest
    defaultLayout $ do
        setTitle (toHtml (socioNome socio))
        $(widgetFile "socios/detalhe")

getSocioEditarR :: SocioId -> Handler Html
getSocioEditarR socioId = do
    socio <- runDB $ get404 socioId
    (formulario, enctype) <- generateFormPost (socioForm (Just socio))
    paginaFormulario "Editar sócio" (SocioR socioId) formulario enctype

postSocioR :: SocioId -> Handler Html
postSocioR socioId = do
    anterior <- runDB $ get404 socioId
    ((resultado, formulario), enctype) <- runFormPost (socioForm Nothing)
    let reexibir = paginaFormulario "Editar sócio" (SocioR socioId) formulario enctype
    case resultado of
        FormSuccess dados -> do
            repetido <- emailEmUso (dadosEmail dados) (Just socioId)
            if repetido
                then mensagem "danger" emailRepetido >> reexibir
                else do
                    resolvido <- resolverEndereco (Just anterior) dados
                    case resolvido of
                        Left erro -> mensagem "danger" erro >> reexibir
                        Right socio -> do
                            runDB $ replace socioId socio
                            mensagem "success" "Sócio atualizado."
                            redirect (SocioR socioId)
        _ -> reexibir

postSocioExcluirR :: SocioId -> Handler Html
postSocioExcluirR socioId = do
    _ <- runDB $ get404 socioId
    (emprestimos, reservas) <- runDB $ (,)
        <$> count [EmprestimoSocioId ==. socioId]
        <*> count [ReservaSocioId ==. socioId]
    if emprestimos > 0 || reservas > 0
        then do
            mensagem "danger" ("Não é possível excluir: o sócio tem " <> tshow emprestimos <> " empréstimo(s) e " <> tshow reservas <> " reserva(s) registrados.")
            redirect (SocioR socioId)
        else do
            runDB $ delete socioId
            mensagem "success" "Sócio excluído."
            redirect SociosR

cidadeUf :: Socio -> Text
cidadeUf socio = case (socioCidade socio, socioUf socio) of
    (Just cidade, Just uf) -> cidade <> "/" <> uf
    (Just cidade, Nothing) -> cidade
    _ -> "—"

enderecoCompleto :: Socio -> Maybe Text
enderecoCompleto socio = do
    logradouro <- socioLogradouro socio
    let numero = maybe "" (", " <>) (socioNumero socio)
        bairro = maybe "" (" — " <>) (socioBairro socio)
    return (logradouro <> numero <> bairro <> ", " <> cidadeUf socio)
