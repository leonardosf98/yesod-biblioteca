{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Emprestimo
    ( prazoDias
    , limiteAbertos
    , multaPorDiaCentavos
    , hoje
    , calcularMulta
    , realizarEmprestimo
    , registrarDevolucao
    , cancelarEmprestimo
    , formatarCentavos
    ) where

import ClassyPrelude.Yesod
import Data.Time (addDays, diffDays, getCurrentTimeZone, localDay, utcToLocalTime)
import Database.Persist.Sql (updateWhereCount)
import Model
import Model.Tipos

prazoDias :: Integer
prazoDias = 14

limiteAbertos :: Int
limiteAbertos = 3

multaPorDiaCentavos :: Int
multaPorDiaCentavos = 100

hoje :: MonadIO m => m Day
hoje = liftIO $ do
    fuso <- getCurrentTimeZone
    localDay . utcToLocalTime fuso <$> getCurrentTime

calcularMulta :: Day -> Day -> Int
calcularMulta prevista devolucao = fromIntegral (max 0 (diffDays devolucao prevista)) * multaPorDiaCentavos

formatarCentavos :: Int -> Text
formatarCentavos centavos = "R$ " <> tshow reais <> "," <> (if resto < 10 then "0" else "") <> tshow resto
  where
    (reais, resto) = centavos `divMod` 100

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
            | abertos >= limiteAbertos -> return (Left ("O sócio já tem " <> tshow abertos <> " empréstimos em aberto (limite " <> tshow limiteAbertos <> ")."))
            | otherwise -> do
                reservado <- updateWhereCount
                    [ExemplarId ==. exemplarId, ExemplarDisponivel ==. True]
                    [ExemplarDisponivel =. False]
                if reservado == 0
                    then return (Left "Exemplar indisponível.")
                    else Right <$> insert Emprestimo
                        { emprestimoExemplarId = exemplarId
                        , emprestimoSocioId = socioId
                        , emprestimoDataEmprestimo = dia
                        , emprestimoDataPrevista = addDays prazoDias dia
                        , emprestimoDataDevolucao = Nothing
                        , emprestimoMultaCentavos = 0
                        }

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

cancelarEmprestimo :: MonadIO m => EmprestimoId -> ReaderT SqlBackend m (Either Text ())
cancelarEmprestimo emprestimoId = do
    encontrado <- get emprestimoId
    case encontrado of
        Nothing -> return (Left "Empréstimo não encontrado.")
        Just emprestimo
            | isJust (emprestimoDataDevolucao emprestimo) -> return (Left "Empréstimo já devolvido faz parte do histórico e não pode ser excluído.")
            | otherwise -> do
                delete emprestimoId
                update (emprestimoExemplarId emprestimo) [ExemplarDisponivel =. True]
                return (Right ())
