{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.AreaDoSocio
    ( getEuEmprestimosR
    , postLivroPedidosR
    , deleteEuPedidoR
    , postEuRenovacaoR
    , postLivroReservasR
    , deleteEuReservaR
    ) where

import Import
import Api.Relacionados
import Api.Resposta
import Data.List (findIndex)
import qualified Data.Map.Strict as Map
import Regras.Comum (hoje)
import Regras.Emprestimo (pendencias, renovarEmprestimo)
import Regras.Pedido (cancelarPedido, expirarPedidos, pedirLivro)
import Regras.Politica (limiteAbertos)
import Regras.Reserva (cancelarReserva, criarReserva, filaDeReservas)

socioAtual :: Handler SocioId
socioAtual = do
    Entity _ usuario <- exigirUsuario
    maybe (permissionDenied "Conta sem sócio vinculado.") return (userSocioId usuario)

posicaoNaFila :: MonadIO m => Entity Reserva -> ReaderT SqlBackend m Int
posicaoNaFila (Entity reservaId reserva) = do
    fila <- filaDeReservas (reservaLivroId reserva)
    return $ maybe 0 (+ 1) (findIndex ((== reservaId) . entityKey) fila)

getEuEmprestimosR :: Handler Value
getEuEmprestimosR = do
    socioId <- socioAtual
    agora <- liftIO getCurrentTime
    dia <- hoje
    (emprestimos, pedidos, reservas, posicoes, rel, bloqueios) <- runDB $ do
        expirarPedidos agora
        emprestimos <- selectList [EmprestimoSocioId ==. socioId] [Desc EmprestimoDataEmprestimo]
        pedidos <- selectList [PedidoSocioId ==. socioId, PedidoStatus ==. PedidoAguardando] [Asc PedidoLimiteRetirada]
        reservas <- selectList [ReservaSocioId ==. socioId, ReservaStatus ==. Ativa] [Asc ReservaDataReserva]
        posicoes <- forM reservas $ \r -> (,) (entityKey r) <$> posicaoNaFila r
        rel <- carregarRelacionados []
            (map (emprestimoExemplarId . entityVal) emprestimos ++ map (pedidoExemplarId . entityVal) pedidos)
            (map (reservaLivroId . entityVal) reservas)
        bloqueios <- pendencias socioId dia
        return (emprestimos, pedidos, reservas, Map.fromList posicoes, rel, bloqueios)
    let abertos = filter (isNothing . emprestimoDataDevolucao . entityVal) emprestimos
        emprestimoJson (Entity k e) = object
            [ "id" .= k
            , "livro" .= livroDoExemplar rel (emprestimoExemplarId e)
            , "exemplar" .= codigoDoExemplar rel (emprestimoExemplarId e)
            , "dataEmprestimo" .= emprestimoDataEmprestimo e
            , "dataPrevista" .= emprestimoDataPrevista e
            , "dataDevolucao" .= emprestimoDataDevolucao e
            , "atrasado" .= (isNothing (emprestimoDataDevolucao e) && emprestimoDataPrevista e < dia)
            , "renovacoes" .= emprestimoRenovacoes e
            , "multaCentavos" .= emprestimoMultaCentavos e
            , "multaPaga" .= isJust (emprestimoMultaPagaEm e)
            ]
        pedidoJson (Entity k p) = object
            [ "id" .= k
            , "codigo" .= pedidoCodigo p
            , "livro" .= livroDoExemplar rel (pedidoExemplarId p)
            , "limiteRetirada" .= pedidoLimiteRetirada p
            ]
        reservaJson (Entity k r) = object
            [ "id" .= k
            , "livro" .= livroResumo rel (reservaLivroId r)
            , "posicao" .= Map.findWithDefault 0 k posicoes
            ]
    returnJson $ object
        [ "emprestimos" .= map emprestimoJson emprestimos
        , "pedidos" .= map pedidoJson pedidos
        , "reservas" .= map reservaJson reservas
        , "pendencias" .= bloqueios
        , "emUso" .= (length abertos + length pedidos)
        , "limite" .= limiteAbertos
        ]

postLivroPedidosR :: LivroId -> Handler Value
postLivroPedidosR livroId = do
    socioId <- socioAtual
    agora <- liftIO getCurrentTime
    dia <- hoje
    Entity pedidoId pedido <- runDB (get404 livroId >> pedirLivro socioId livroId agora dia) >>= ouConflito
    criado $ object
        [ "id" .= pedidoId
        , "codigo" .= pedidoCodigo pedido
        , "limiteRetirada" .= pedidoLimiteRetirada pedido
        ]

deleteEuPedidoR :: PedidoId -> Handler Value
deleteEuPedidoR pedidoId = do
    socioId <- socioAtual
    runDB (cancelarPedido socioId pedidoId) >>= either (recusar status404) return
    semConteudo

postEuRenovacaoR :: EmprestimoId -> Handler Value
postEuRenovacaoR emprestimoId = do
    socioId <- socioAtual
    dia <- hoje
    novaData <- runDB (renovarEmprestimo socioId emprestimoId dia) >>= ouConflito
    returnJson $ object ["dataPrevista" .= novaData]

postLivroReservasR :: LivroId -> Handler Value
postLivroReservasR livroId = do
    socioId <- socioAtual
    dia <- hoje
    reservaId <- runDB (get404 livroId >> criarReserva socioId livroId dia) >>= ouConflito
    posicao <- runDB $ getJustEntity reservaId >>= posicaoNaFila
    criado $ object ["id" .= reservaId, "posicao" .= posicao]

deleteEuReservaR :: ReservaId -> Handler Value
deleteEuReservaR reservaId = do
    socioId <- socioAtual
    reserva <- runDB $ get reservaId
    case reserva of
        Just r | reservaSocioId r == socioId -> do
            runDB (cancelarReserva reservaId) >>= ouConflito
            semConteudo
        _ -> recusar status404 "Reserva não encontrada."
