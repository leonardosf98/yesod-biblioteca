{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Socios
    ( getSociosR
    , postSociosR
    , getSocioR
    , putSocioR
    , deleteSocioR
    ) where

import Import
import Api.Filtro (contem, parametroDeBusca)
import Api.Relacionados
import Api.Resposta
import Api.Validacao
import qualified Data.Text as T
import Regras.Comum (hoje)
import Regras.Emprestimo (pendencias)
import Regras.Politica (limiteAbertos)
import Regras.Socio

getSociosR :: Handler Value
getSociosR = do
    busca <- parametroDeBusca
    dia <- hoje
    resultado <- runDB $ do
        let filtro = case busca of
                Nothing -> []
                Just termo -> [contem SocioNome termo] ||. [contem SocioEmail termo]
        socios <- selectList filtro [Asc SocioNome, LimitTo 20]
        forM socios $ \(Entity k s) -> do
            abertos <- count [EmprestimoSocioId ==. k, EmprestimoDataDevolucao ==. Nothing]
            aguardando <- count [PedidoSocioId ==. k, PedidoStatus ==. PedidoAguardando]
            bloqueios <- pendencias k dia
            conta <- exists [UserSocioId ==. Just k]
            return $ object
                [ "id" .= k
                , "nome" .= socioNome s
                , "email" .= socioEmail s
                , "cidade" .= socioCidade s
                , "emUso" .= (abertos + aguardando)
                , "pendencias" .= bloqueios
                , "contaAtiva" .= conta
                ]
    returnJson $ object ["socios" .= resultado, "limite" .= limiteAbertos]

lerSocio :: Maybe Socio -> Handler Socio
lerSocio anterior = do
    o <- requireCheckJsonBody
    socio <- exigirValido $ Socio
        <$> texto "nome" 120 (campoTexto o "nome")
        <*> exigido "email" "Informe um e-mail válido." (campoTexto o "email" >>= emailValido)
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

emailValido :: Text -> Maybe Text
emailValido e
    | T.length minusculo <= 120
        && not (null usuario)
        && "." `T.isInfixOf` T.drop 1 dominio
        && not (" " `T.isInfixOf` minusculo) = Just minusculo
    | otherwise = Nothing
  where
    minusculo = T.toLower e
    (usuario, dominio) = T.breakOn "@" minusculo

garantirEmailLivre :: Text -> Maybe SocioId -> Handler ()
garantirEmailLivre email proprio = do
    garantirUnico (UniqueSocioEmail email) proprio "Já existe um sócio com esse e-mail."
    conta <- runDB $ getBy (UniqueUser email)
    when (maybe False ((/= proprio) . userSocioId . entityVal) conta) $
        conflito "Esse e-mail já é login de outra conta."

postSociosR :: Handler Value
postSociosR = do
    socio <- lerSocio Nothing
    garantirEmailLivre (socioEmail socio) Nothing
    socioId <- runDB $ insert socio
    criado $ object ["id" .= socioId]

putSocioR :: SocioId -> Handler Value
putSocioR socioId = do
    anterior <- runDB $ get404 socioId
    socio <- lerSocio (Just anterior)
    garantirEmailLivre (socioEmail socio) (Just socioId)
    runDB $ do
        replace socioId socio
        updateWhere [UserSocioId ==. Just socioId] [UserIdent =. socioEmail socio]
    returnJson $ object ["id" .= socioId]

deleteSocioR :: SocioId -> Handler Value
deleteSocioR socioId = do
    runDB $ do
        _ <- get404 socioId
        emprestimos <- count [EmprestimoSocioId ==. socioId]
        reservas <- count [ReservaSocioId ==. socioId]
        pedidos <- count [PedidoSocioId ==. socioId]
        when (emprestimos + reservas + pedidos > 0) $ conflito $
            "Não é possível excluir: o sócio tem " <> tshow emprestimos <> " empréstimo(s), "
                <> tshow reservas <> " reserva(s) e " <> tshow pedidos <> " pedido(s) registrados."
        deleteWhere [UserSocioId ==. Just socioId]
        delete socioId
    semConteudo

getSocioR :: SocioId -> Handler Value
getSocioR socioId = do
    dia <- hoje
    (socio, emprestimos, reservas, rel, bloqueios, conta) <- runDB $ do
        socio <- get404 socioId
        emprestimos <- selectList [EmprestimoSocioId ==. socioId] [Desc EmprestimoDataEmprestimo]
        reservas <- selectList [ReservaSocioId ==. socioId, ReservaStatus ==. Ativa] []
        rel <- carregarRelacionados []
            (map (emprestimoExemplarId . entityVal) emprestimos)
            (map (reservaLivroId . entityVal) reservas)
        bloqueios <- pendencias socioId dia
        conta <- exists [UserSocioId ==. Just socioId]
        return (socio, emprestimos, reservas, rel, bloqueios, conta)
    let emprestimoJson (Entity k e) = object
            [ "id" .= k
            , "livro" .= tituloPeloExemplar rel (emprestimoExemplarId e)
            , "exemplar" .= codigoDoExemplar rel (emprestimoExemplarId e)
            , "dataEmprestimo" .= emprestimoDataEmprestimo e
            , "dataPrevista" .= emprestimoDataPrevista e
            , "dataDevolucao" .= emprestimoDataDevolucao e
            , "multaCentavos" .= emprestimoMultaCentavos e
            , "multaPaga" .= isJust (emprestimoMultaPagaEm e)
            ]
        reservaJson (Entity k r) = object ["id" .= k, "livro" .= tituloDoLivro rel (reservaLivroId r)]
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
        , "emprestimos" .= map emprestimoJson emprestimos
        , "reservas" .= map reservaJson reservas
        ]
