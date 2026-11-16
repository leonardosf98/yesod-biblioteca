{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiWayIf #-}
module Regras.Reserva
    ( criarReserva
    , cancelarReserva
    , atenderReserva
    , filaDeReservas
    ) where

import ClassyPrelude.Yesod
import Model
import Model.Tipos
import Database.Persist.Sql (updateWhereCount)

criarReserva :: MonadIO m => SocioId -> LivroId -> Day -> ReaderT SqlBackend m (Either Text ReservaId)
criarReserva socioId livroId dia = do
    disponiveis <- count [ExemplarLivroId ==. livroId, ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido]
    repetida <- count [ReservaSocioId ==. socioId, ReservaLivroId ==. livroId, ReservaStatus ==. Ativa]
    if
        | disponiveis > 0 -> return (Left "Há exemplar disponível: faça o empréstimo em vez de reservar.")
        | repetida > 0 -> return (Left "O sócio já tem uma reserva ativa para este livro.")
        | otherwise -> Right <$> insert (Reserva livroId socioId dia Ativa)

cancelarReserva :: MonadIO m => ReservaId -> ReaderT SqlBackend m (Either Text ())
cancelarReserva reservaId = do
    alteradas <- updateWhereCount [ReservaId ==. reservaId, ReservaStatus ==. Ativa] [ReservaStatus =. Cancelada]
    return $ if alteradas == 0 then Left "Só reservas ativas podem ser canceladas." else Right ()

atenderReserva :: MonadIO m => SocioId -> LivroId -> ReaderT SqlBackend m ()
atenderReserva socioId livroId =
    updateWhere [ReservaSocioId ==. socioId, ReservaLivroId ==. livroId, ReservaStatus ==. Ativa] [ReservaStatus =. Atendida]

filaDeReservas :: MonadIO m => LivroId -> ReaderT SqlBackend m [Entity Reserva]
filaDeReservas livroId = selectList [ReservaLivroId ==. livroId, ReservaStatus ==. Ativa] [Asc ReservaDataReserva, Asc ReservaId]
