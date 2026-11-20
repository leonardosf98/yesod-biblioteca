{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiWayIf #-}
module Regras.Emprestimo
    ( calcularMulta
    , pendencias
    , novoEmprestimo
    , separarExemplar
    , realizarEmprestimo
    , registrarDevolucao
    , renovarEmprestimo
    , registrarPagamentoMulta
    ) where

import ClassyPrelude.Yesod
import Data.Time (addDays, diffDays)
import Database.Persist.Sql (updateWhereCount)
import Model
import Model.Tipos
import Regras.Comum (formatarCentavos)
import Regras.Politica (diasRenovacao, limiteAbertos, multaPorDiaCentavos, prazoDias)
import Regras.Reserva (atenderReserva, filaDeReservas)

calcularMulta :: Day -> Day -> Int
calcularMulta prevista devolucao = fromIntegral (max 0 (diffDays devolucao prevista)) * multaPorDiaCentavos

pendencias :: MonadIO m => SocioId -> Day -> ReaderT SqlBackend m [Text]
pendencias socioId dia = do
    multas <- selectList [EmprestimoSocioId ==. socioId, EmprestimoMultaCentavos >. 0, EmprestimoMultaPagaEm ==. Nothing] []
    atrasados <- count [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing, EmprestimoDataPrevista <. dia]
    let totalDeMultas = sum (map (emprestimoMultaCentavos . entityVal) multas)
    return $
        [ "Há " <> formatarCentavos totalDeMultas <> " de multa em aberto; pague no balcão para liberar novos pedidos."
        | totalDeMultas > 0
        ]
        ++ ["Há empréstimo atrasado; devolva no balcão para liberar novos pedidos." | atrasados > 0]

novoEmprestimo :: SocioId -> ExemplarId -> Day -> Emprestimo
novoEmprestimo socioId exemplarId dia = Emprestimo
    { emprestimoExemplarId = exemplarId
    , emprestimoSocioId = socioId
    , emprestimoDataEmprestimo = dia
    , emprestimoDataPrevista = addDays prazoDias dia
    , emprestimoDataDevolucao = Nothing
    , emprestimoMultaCentavos = 0
    , emprestimoRenovacoes = 0
    , emprestimoMultaPagaEm = Nothing
    }

realizarEmprestimo :: MonadIO m => SocioId -> ExemplarId -> Day -> ReaderT SqlBackend m (Either Text EmprestimoId)
realizarEmprestimo socioId exemplarId dia = do
    socio <- get socioId
    exemplar <- get exemplarId
    abertos <- count [EmprestimoSocioId ==. socioId, EmprestimoDataDevolucao ==. Nothing]
    case (socio, exemplar) of
        (Nothing, _) -> return (Left "Sócio não encontrado.")
        (_, Nothing) -> return (Left "Exemplar não encontrado.")
        (_, Just e)
            | exemplarEstado e == Perdido -> return (Left "Exemplar marcado como perdido.")
            | abertos >= limiteAbertos -> return . Left $
                "O sócio já tem " <> tshow abertos <> " empréstimos em aberto (limite " <> tshow limiteAbertos <> ")."
            | otherwise -> do
                separado <- separarExemplar exemplarId
                if not separado
                    then return (Left "Exemplar indisponível.")
                    else do
                        atenderReserva socioId (exemplarLivroId e)
                        Right <$> insert (novoEmprestimo socioId exemplarId dia)

-- Marca como indisponível só se ainda estiver livre: duas requisições ao mesmo
-- tempo não conseguem separar o mesmo exemplar.
separarExemplar :: MonadIO m => ExemplarId -> ReaderT SqlBackend m Bool
separarExemplar exemplarId = do
    alterados <- updateWhereCount [ExemplarId ==. exemplarId, ExemplarDisponivel ==. True] [ExemplarDisponivel =. False]
    return (alterados == 1)

registrarDevolucao :: MonadIO m => EmprestimoId -> Day -> ReaderT SqlBackend m (Either Text Int)
registrarDevolucao emprestimoId dia = do
    encontrado <- get emprestimoId
    case encontrado of
        Nothing -> return (Left "Empréstimo não encontrado.")
        Just emprestimo
            | isJust (emprestimoDataDevolucao emprestimo) -> return (Left "Esse empréstimo já foi devolvido.")
            | otherwise -> do
                let multa = calcularMulta (emprestimoDataPrevista emprestimo) dia
                update emprestimoId [EmprestimoDataDevolucao =. Just dia, EmprestimoMultaCentavos =. multa]
                update (emprestimoExemplarId emprestimo) [ExemplarDisponivel =. True]
                return (Right multa)

renovarEmprestimo :: MonadIO m => SocioId -> EmprestimoId -> Day -> ReaderT SqlBackend m (Either Text Day)
renovarEmprestimo socioId emprestimoId dia = do
    encontrado <- get emprestimoId
    case encontrado of
        Just e | emprestimoSocioId e == socioId && isNothing (emprestimoDataDevolucao e) -> do
            bloqueios <- pendencias socioId dia
            exemplar <- get (emprestimoExemplarId e)
            fila <- maybe (return []) (filaDeReservas . exemplarLivroId) exemplar
            if  | emprestimoRenovacoes e > 0 -> return (Left "Esse empréstimo já foi renovado uma vez. Devolva no balcão até o prazo.")
                | emprestimoDataPrevista e < dia -> return (Left "O prazo já venceu; devolva no balcão.")
                | motivo : _ <- bloqueios -> return (Left motivo)
                | not (null fila) -> return (Left "Há fila de reservas para esse livro; não dá para renovar.")
                | otherwise -> do
                    let novaData = addDays diasRenovacao (emprestimoDataPrevista e)
                    update emprestimoId [EmprestimoDataPrevista =. novaData, EmprestimoRenovacoes +=. 1]
                    return (Right novaData)
        _ -> return (Left "Empréstimo não encontrado.")

registrarPagamentoMulta :: MonadIO m => EmprestimoId -> Day -> ReaderT SqlBackend m (Either Text ())
registrarPagamentoMulta emprestimoId dia = do
    encontrado <- get emprestimoId
    case encontrado of
        Nothing -> return (Left "Empréstimo não encontrado.")
        Just emprestimo
            | emprestimoMultaCentavos emprestimo <= 0 -> return (Left "Esse empréstimo não tem multa.")
            | isJust (emprestimoMultaPagaEm emprestimo) -> return (Left "A multa já foi paga.")
            | otherwise -> Right <$> update emprestimoId [EmprestimoMultaPagaEm =. Just dia]
