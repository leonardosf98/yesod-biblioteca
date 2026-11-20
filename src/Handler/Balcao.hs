{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Balcao
    ( getPainelR
    , getExemplarCodigoR
    , postEmprestimosR
    , postDevolucaoR
    , postPedidoRetiradaR
    , deletePedidoR
    , postPagamentoMultaR
    , deleteReservaR
    ) where

import Import
import Api.Relacionados
import Api.Resposta
import Data.Aeson (withObject)
import Data.Either (isRight)
import Data.Time (diffDays)
import qualified Data.Text as T
import Regras.Comum (hoje)
import Regras.Emprestimo
import Regras.Pedido (atenderFila, cancelarPedidoNoBalcao, confirmarRetirada, expirarPedidos)
import Regras.Reserva (cancelarReserva)

getPainelR :: Handler Value
getPainelR = do
    agora <- liftIO getCurrentTime
    dia <- hoje
    (abertos, exemplares, pedidos, rel) <- runDB $ do
        expirarPedidos agora
        abertos <- selectList [EmprestimoDataDevolucao ==. Nothing] [Asc EmprestimoDataPrevista]
        exemplares <- count [ExemplarEstado !=. Perdido]
        pedidos <- selectList [PedidoStatus ==. PedidoAguardando] [Asc PedidoCriadoEm]
        let emprestimos = map entityVal abertos
            ps = map entityVal pedidos
        rel <- carregarRelacionados
            (map emprestimoSocioId emprestimos ++ map pedidoSocioId ps)
            (map emprestimoExemplarId emprestimos ++ map pedidoExemplarId ps)
            []
        return (abertos, exemplares, pedidos, rel)
    let prevista = emprestimoDataPrevista . entityVal
        atrasados = filter ((< dia) . prevista) abertos
        deHoje = filter ((== dia) . prevista) abertos
        multa e = calcularMulta (emprestimoDataPrevista e) dia
        emprestimoJson (Entity k e) = object
            [ "emprestimoId" .= k
            , "socio" .= socioResumo rel (emprestimoSocioId e)
            , "livro" .= livroDoExemplar rel (emprestimoExemplarId e)
            , "exemplar" .= codigoDoExemplar rel (emprestimoExemplarId e)
            , "dataPrevista" .= emprestimoDataPrevista e
            , "diasAtraso" .= max 0 (diffDays dia (emprestimoDataPrevista e))
            , "multaCentavos" .= multa e
            ]
        pedidoJson (Entity k p) = object
            [ "id" .= k
            , "codigo" .= pedidoCodigo p
            , "socio" .= socioResumo rel (pedidoSocioId p)
            , "livro" .= livroDoExemplar rel (pedidoExemplarId p)
            , "exemplar" .= codigoDoExemplar rel (pedidoExemplarId p)
            , "criadoEm" .= pedidoCriadoEm p
            , "limiteRetirada" .= pedidoLimiteRetirada p
            ]
    returnJson $ object
        [ "resumo" .= object
            [ "abertos" .= length abertos
            , "exemplares" .= exemplares
            , "pedidos" .= length pedidos
            , "atrasados" .= length atrasados
            , "multaAtrasadosCentavos" .= sum (map (multa . entityVal) atrasados)
            , "devolucoesHoje" .= length deHoje
            ]
        , "pedidos" .= map pedidoJson pedidos
        , "atrasados" .= map emprestimoJson atrasados
        , "devolucoesHoje" .= map emprestimoJson deHoje
        ]

getExemplarCodigoR :: Text -> Handler Value
getExemplarCodigoR codigo = do
    dia <- hoje
    (Entity exemplarId exemplar, livro, aberto, rel) <- runDB $ do
        encontrado <- getBy (UniqueCodigo (T.toUpper (T.strip codigo)))
        Entity exemplarId exemplar <- maybe notFound return encontrado
        livro <- get (exemplarLivroId exemplar)
        aberto <- selectFirst [EmprestimoExemplarId ==. exemplarId, EmprestimoDataDevolucao ==. Nothing] []
        rel <- carregarRelacionados (maybe [] (pure . emprestimoSocioId . entityVal) aberto) [] []
        return (Entity exemplarId exemplar, livro, aberto, rel)
    let emprestimoJson (Entity k e) = object
            [ "id" .= k
            , "socio" .= socioResumo rel (emprestimoSocioId e)
            , "dataPrevista" .= emprestimoDataPrevista e
            , "multaCentavos" .= calcularMulta (emprestimoDataPrevista e) dia
            ]
    returnJson $ object
        [ "exemplar" .= object
            [ "id" .= exemplarId
            , "codigo" .= exemplarCodigo exemplar
            , "estado" .= estadoTexto (exemplarEstado exemplar)
            , "disponivel" .= exemplarDisponivel exemplar
            ]
        , "livro" .= object
            [ "id" .= exemplarLivroId exemplar
            , "titulo" .= (livroTitulo <$> livro)
            , "capaUrl" .= (livro >>= livroCapaUrl)
            ]
        , "emprestimo" .= fmap emprestimoJson aberto
        ]

data NovoEmprestimo = NovoEmprestimo SocioId ExemplarId

instance FromJSON NovoEmprestimo where
    parseJSON = withObject "NovoEmprestimo" $ \o ->
        NovoEmprestimo <$> o .: "socioId" <*> o .: "exemplarId"

postEmprestimosR :: Handler Value
postEmprestimosR = do
    NovoEmprestimo socioId exemplarId <- requireCheckJsonBody
    dia <- hoje
    resultado <- runDB $ do
        bloqueios <- pendencias socioId dia
        case bloqueios of
            motivo : _ -> return (Left motivo)
            [] -> realizarEmprestimo socioId exemplarId dia
    emprestimoId <- ouConflito resultado
    emprestimo <- runDB $ getJustEntity emprestimoId
    criado $ object ["id" .= entityKey emprestimo, "dataPrevista" .= emprestimoDataPrevista (entityVal emprestimo)]

postDevolucaoR :: EmprestimoId -> Handler Value
postDevolucaoR emprestimoId = do
    dia <- hoje
    agora <- liftIO getCurrentTime
    resultado <- runDB $ do
        resultado <- registrarDevolucao emprestimoId dia
        when (isRight resultado) $ do
            emprestimo <- getJust emprestimoId
            exemplar <- getJust (emprestimoExemplarId emprestimo)
            atenderFila (exemplarLivroId exemplar) agora
        return resultado
    multa <- ouConflito resultado
    returnJson $ object ["multaCentavos" .= multa]

postPedidoRetiradaR :: PedidoId -> Handler Value
postPedidoRetiradaR pedidoId = do
    agora <- liftIO getCurrentTime
    dia <- hoje
    emprestimoId <- runDB (confirmarRetirada pedidoId agora dia) >>= ouConflito
    emprestimo <- runDB $ getJustEntity emprestimoId
    criado $ object
        [ "emprestimoId" .= entityKey emprestimo
        , "dataPrevista" .= emprestimoDataPrevista (entityVal emprestimo)
        ]

deletePedidoR :: PedidoId -> Handler Value
deletePedidoR pedidoId = do
    runDB (get404 pedidoId >> cancelarPedidoNoBalcao pedidoId) >>= ouConflito
    semConteudo

postPagamentoMultaR :: EmprestimoId -> Handler Value
postPagamentoMultaR emprestimoId = do
    dia <- hoje
    runDB (registrarPagamentoMulta emprestimoId dia) >>= ouConflito
    semConteudo

deleteReservaR :: ReservaId -> Handler Value
deleteReservaR reservaId = do
    runDB (get404 reservaId >> cancelarReserva reservaId) >>= ouConflito
    semConteudo
