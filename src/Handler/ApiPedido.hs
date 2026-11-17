{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiPedido
    ( postApiLivroPedidosR
    , deleteApiEuPedidoR
    , getApiEuEmprestimosR
    , postApiPedidoRetiradaR
    , postApiEuRenovacaoR
    , postApiLivroReservasR
    , postApiPagamentoMultaR
    ) where

import Import
import Data.List (findIndex)
import qualified Data.Map.Strict as Map
import Regras.Emprestimo (hoje, limiteAbertos, registrarPagamentoMulta)
import Regras.Pedido
import Regras.Reserva (criarReserva, filaDeReservas)

socioAtual :: Handler SocioId
socioAtual = do
    Entity _ usuario <- requireAuth
    maybe (permissionDenied "Conta sem sócio vinculado.") return (userSocioId usuario)

recusar :: Status -> Text -> Handler a
recusar status mensagemErro = sendStatusJSON status $ object ["erro" .= mensagemErro]

postApiLivroPedidosR :: LivroId -> Handler Value
postApiLivroPedidosR livroId = do
    socioId <- socioAtual
    agora <- liftIO getCurrentTime
    dia <- hoje
    resultado <- runDB $ get404 livroId >> pedirLivro socioId livroId agora dia
    case resultado of
        Left motivo -> recusar status409 motivo
        Right (Entity pedidoId p) -> sendStatusJSON status201 $ object
            [ "id" .= pedidoId
            , "codigo" .= pedidoCodigo p
            , "limiteRetirada" .= pedidoLimiteRetirada p
            ]

deleteApiEuPedidoR :: PedidoId -> Handler Value
deleteApiEuPedidoR pedidoId = do
    socioId <- socioAtual
    resultado <- runDB $ cancelarPedido socioId pedidoId
    either (recusar status404) (const (sendResponseStatus status204 ())) resultado

postApiPedidoRetiradaR :: PedidoId -> Handler Value
postApiPedidoRetiradaR pedidoId = do
    agora <- liftIO getCurrentTime
    dia <- hoje
    resultado <- runDB $ confirmarRetirada pedidoId agora dia
    case resultado of
        Left motivo -> recusar status409 motivo
        Right emprestimoId -> do
            emprestimo <- runDB $ getJust emprestimoId
            sendStatusJSON status201 $ object
                ["emprestimoId" .= emprestimoId, "dataPrevista" .= emprestimoDataPrevista emprestimo]

getApiEuEmprestimosR :: Handler Value
getApiEuEmprestimosR = do
    socioId <- socioAtual
    agora <- liftIO getCurrentTime
    dia <- hoje
    (emprestimos, pedidos, reservas, livroDoExemplar, livros, codigos, posicoes, bloqueios) <- runDB $ do
        expirarPedidos agora
        emprestimos <- selectList [EmprestimoSocioId ==. socioId] [Desc EmprestimoDataEmprestimo]
        pedidos <- selectList [PedidoSocioId ==. socioId, PedidoStatus ==. PedidoAguardando] [Asc PedidoLimiteRetirada]
        reservas <- selectList [ReservaSocioId ==. socioId, ReservaStatus ==. Ativa] [Asc ReservaDataReserva]
        exemplares <- selectList [ExemplarId <-. (map (emprestimoExemplarId . entityVal) emprestimos ++ map (pedidoExemplarId . entityVal) pedidos)] []
        let livroDoExemplar = Map.fromList [(k, exemplarLivroId v) | Entity k v <- exemplares]
            livrosIds = Map.elems livroDoExemplar ++ map (reservaLivroId . entityVal) reservas
        livros <- Map.fromList . map (\(Entity k v) -> (k, v)) <$> selectList [LivroId <-. livrosIds] []
        posicoes <- forM reservas $ \(Entity reservaId r) -> do
            fila <- filaDeReservas (reservaLivroId r)
            return (reservaId, maybe 0 (+ 1) (findIndex ((== reservaId) . entityKey) fila))
        bloqueios <- pendencias socioId dia
        let codigos = Map.fromList [(k, exemplarCodigo v) | Entity k v <- exemplares]
        return (emprestimos, pedidos, reservas, livroDoExemplar, livros, codigos, Map.fromList posicoes, bloqueios)
    let livroJson livroId = object
            [ "id" .= livroId
            , "titulo" .= maybe "—" livroTitulo (Map.lookup livroId livros)
            , "capaUrl" .= (Map.lookup livroId livros >>= livroCapaUrl)
            ]
        doExemplar exemplarId = maybe (object []) livroJson (Map.lookup exemplarId livroDoExemplar)
        abertos = filter (isNothing . emprestimoDataDevolucao . entityVal) emprestimos
    returnJson $ object
        [ "emprestimos" .=
            [ object
                [ "id" .= k
                , "livro" .= doExemplar (emprestimoExemplarId e)
                , "exemplar" .= Map.lookup (emprestimoExemplarId e) codigos
                , "dataEmprestimo" .= emprestimoDataEmprestimo e
                , "dataPrevista" .= emprestimoDataPrevista e
                , "dataDevolucao" .= emprestimoDataDevolucao e
                , "atrasado" .= (isNothing (emprestimoDataDevolucao e) && emprestimoDataPrevista e < dia)
                , "renovacoes" .= emprestimoRenovacoes e
                , "multaCentavos" .= emprestimoMultaCentavos e
                , "multaPaga" .= isJust (emprestimoMultaPagaEm e)
                ]
            | Entity k e <- emprestimos
            ]
        , "pedidos" .=
            [ object
                [ "id" .= k
                , "codigo" .= pedidoCodigo p
                , "livro" .= doExemplar (pedidoExemplarId p)
                , "limiteRetirada" .= pedidoLimiteRetirada p
                ]
            | Entity k p <- pedidos
            ]
        , "reservas" .=
            [ object
                [ "id" .= k
                , "livro" .= livroJson (reservaLivroId r)
                , "posicao" .= Map.findWithDefault 0 k posicoes
                ]
            | Entity k r <- reservas
            ]
        , "pendencias" .= bloqueios
        , "emUso" .= (length abertos + length pedidos)
        , "limite" .= limiteAbertos
        ]

postApiEuRenovacaoR :: EmprestimoId -> Handler Value
postApiEuRenovacaoR emprestimoId = do
    socioId <- socioAtual
    dia <- hoje
    resultado <- runDB $ renovarEmprestimo socioId emprestimoId dia
    case resultado of
        Left motivo -> recusar status409 motivo
        Right novaData -> returnJson $ object ["dataPrevista" .= novaData]

postApiLivroReservasR :: LivroId -> Handler Value
postApiLivroReservasR livroId = do
    socioId <- socioAtual
    dia <- hoje
    resultado <- runDB $ get404 livroId >> criarReserva socioId livroId dia
    case resultado of
        Left motivo -> recusar status409 motivo
        Right reservaId -> do
            posicao <- runDB $ length . takeWhile ((/= reservaId) . entityKey) <$> filaDeReservas livroId
            sendStatusJSON status201 $ object ["id" .= reservaId, "posicao" .= (posicao + 1)]

postApiPagamentoMultaR :: EmprestimoId -> Handler Value
postApiPagamentoMultaR emprestimoId = do
    dia <- hoje
    resultado <- runDB $ registrarPagamentoMulta emprestimoId dia
    either (recusar status409) (const (sendResponseStatus status204 ())) resultado
