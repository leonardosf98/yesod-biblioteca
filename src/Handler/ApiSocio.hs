{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiSocio
    ( postApiSociosR
    , getApiSocioR
    , putApiSocioR
    , deleteApiSocioR
    ) where

import Import
import Api.Validacao
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Regras.Emprestimo (hoje)
import Regras.Pedido (pendencias)
import Regras.Socio

lerSocio :: Maybe Socio -> Handler Socio
lerSocio anterior = do
    o <- requireCheckJsonBody
    socio <- exigirValido $ Socio
        <$> texto "nome" 120 (campoTexto o "nome")
        <*> maybe (falha "email" "Informe um e-mail válido.") pure (campoTexto o "email" >>= emailValido)
        <*> opcional "telefone" "Telefone deve ter DDD + 8 ou 9 dígitos." (somenteDigitos [10, 11]) (campoTexto o "telefone")
        <*> opcional "cep" "CEP deve ter 8 dígitos." (somenteDigitos [8]) (campoTexto o "cep")
        <*> pure Nothing
        <*> textoOpcional "numero" 10 (campoTexto o "numero")
        <*> pure Nothing
        <*> pure Nothing
        <*> pure Nothing
    manager <- getsYesod appHttpManager
    completo <- liftIO $ completarEndereco manager anterior socio
    either (exigirValido . falha "cep") return completo
  where
    opcional nome mensagemErro validar = maybe (pure Nothing) (maybe (falha nome mensagemErro) (pure . Just) . validar)
    emailValido e =
        let minusculo = T.toLower e
            (usuario, dominio) = T.breakOn "@" minusculo
        in if T.length minusculo <= 120 && not (null usuario) && "." `T.isInfixOf` T.drop 1 dominio && not (" " `T.isInfixOf` minusculo)
            then Just minusculo
            else Nothing

emailRepetido :: Text -> Maybe SocioId -> Handler ()
emailRepetido email proprio = do
    (socio, usuario) <- runDB $ (,) <$> getBy (UniqueSocioEmail email) <*> getBy (UniqueUser email)
    when (maybe False ((/= proprio) . Just . entityKey) socio) $ conflito "Já existe um sócio com esse e-mail."
    when (maybe False ((/= proprio) . userSocioId . entityVal) usuario) $ conflito "Esse e-mail já é login de outra conta."

postApiSociosR :: Handler Value
postApiSociosR = do
    socio <- lerSocio Nothing
    emailRepetido (socioEmail socio) Nothing
    socioId <- runDB $ insert socio
    sendStatusJSON status201 $ object ["id" .= socioId]

putApiSocioR :: SocioId -> Handler Value
putApiSocioR socioId = do
    anterior <- runDB $ get404 socioId
    socio <- lerSocio (Just anterior)
    emailRepetido (socioEmail socio) (Just socioId)
    runDB $ do
        replace socioId socio
        updateWhere [UserSocioId ==. Just socioId] [UserIdent =. socioEmail socio]
    returnJson $ object ["id" .= socioId]

deleteApiSocioR :: SocioId -> Handler Value
deleteApiSocioR socioId = do
    _ <- runDB $ get404 socioId
    (emprestimos, reservas, pedidos) <- runDB $ (,,)
        <$> count [EmprestimoSocioId ==. socioId]
        <*> count [ReservaSocioId ==. socioId]
        <*> count [PedidoSocioId ==. socioId]
    when (emprestimos + reservas + pedidos > 0) $
        conflito ("Não é possível excluir: o sócio tem " <> tshow emprestimos <> " empréstimo(s), " <> tshow reservas <> " reserva(s) e " <> tshow pedidos <> " pedido(s) registrados.")
    runDB $ do
        usuarios <- selectKeysList [UserSocioId ==. Just socioId] []
        deleteWhere [EmailUserId <-. map Just usuarios]
        deleteWhere [UserId <-. usuarios]
        delete socioId
    sendResponseStatus status204 ()

getApiSocioR :: SocioId -> Handler Value
getApiSocioR socioId = do
    dia <- hoje
    (socio, emprestimos, reservas, livros, codigos, bloqueios, conta) <- runDB $ do
        socio <- get404 socioId
        emprestimos <- selectList [EmprestimoSocioId ==. socioId] [Desc EmprestimoDataEmprestimo]
        reservas <- selectList [ReservaSocioId ==. socioId, ReservaStatus ==. Ativa] []
        exemplares <- selectList [ExemplarId <-. map (emprestimoExemplarId . entityVal) emprestimos] []
        ls <- selectList [LivroId <-. (map (exemplarLivroId . entityVal) exemplares ++ map (reservaLivroId . entityVal) reservas)] []
        bloqueios <- pendencias socioId dia
        conta <- exists [UserSocioId ==. Just socioId]
        let livros = Map.fromList [(k, livroTitulo v) | Entity k v <- ls]
            codigos = Map.fromList [(k, v) | Entity k v <- exemplares]
        return (socio, emprestimos, reservas, livros, codigos, bloqueios, conta)
    let tituloDoExemplar k = Map.lookup k codigos >>= (`Map.lookup` livros) . exemplarLivroId
    returnJson $ object
        [ "id" .= socioId
        , "nome" .= socioNome socio
        , "email" .= socioEmail socio
        , "telefone" .= socioTelefone socio
        , "cep" .= socioCep socio
        , "logradouro" .= socioLogradouro socio
        , "numero" .= socioNumero socio
        , "bairro" .= socioBairro socio
        , "cidade" .= socioCidade socio
        , "uf" .= socioUf socio
        , "contaAtiva" .= conta
        , "pendencias" .= bloqueios
        , "emprestimos" .=
            [ object
                [ "id" .= k
                , "livro" .= tituloDoExemplar (emprestimoExemplarId e)
                , "exemplar" .= (exemplarCodigo <$> Map.lookup (emprestimoExemplarId e) codigos)
                , "dataEmprestimo" .= emprestimoDataEmprestimo e
                , "dataPrevista" .= emprestimoDataPrevista e
                , "dataDevolucao" .= emprestimoDataDevolucao e
                , "multaCentavos" .= emprestimoMultaCentavos e
                , "multaPaga" .= isJust (emprestimoMultaPagaEm e)
                ]
            | Entity k e <- emprestimos
            ]
        , "reservas" .= [object ["id" .= k, "livro" .= Map.lookup (reservaLivroId r) livros] | Entity k r <- reservas]
        ]
