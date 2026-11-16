{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.ReservaSpec (spec) where

import Data.Time (fromGregorian)
import Regras.Emprestimo (realizarEmprestimo)
import Regras.Reserva
import TestImport

dia :: Day
dia = fromGregorian 2026 11 2

novoSocio :: Text -> YesodExample App SocioId
novoSocio email = runDB $ insert (Socio email email Nothing Nothing Nothing Nothing Nothing Nothing Nothing)

livroComExemplar :: Bool -> YesodExample App (LivroId, ExemplarId)
livroComExemplar disponivel = runDB $ do
    categoriaId <- insert (Categoria "Romance" Nothing)
    livroId <- insert (Livro "Livro" Nothing Nothing Nothing Nothing Nothing categoriaId)
    exemplarId <- insert (Exemplar livroId "A-1" Bom disponivel)
    return (livroId, exemplarId)

reservar :: SocioId -> LivroId -> YesodExample App ReservaId
reservar socioId livroId = runDB (criarReserva socioId livroId dia) >>= either (error . unpack) return

spec :: Spec
spec = withApp $ describe "regras de reserva" $ do
    it "não reserva livro com exemplar disponível" $ do
        socioId <- novoSocio "a@example.com"
        (livroId, _) <- livroComExemplar True
        resultado <- runDB $ criarReserva socioId livroId dia
        assertEq "recusada" (Left "Há exemplar disponível: faça o empréstimo em vez de reservar.") (void resultado)

    it "reserva livro sem exemplar disponível, uma vez por sócio" $ do
        socioId <- novoSocio "a@example.com"
        (livroId, _) <- livroComExemplar False
        _ <- reservar socioId livroId
        segunda <- runDB $ criarReserva socioId livroId dia
        assertEq "repetida recusada" (Left "O sócio já tem uma reserva ativa para este livro.") (void segunda)

    it "cancela só reserva ativa" $ do
        socioId <- novoSocio "a@example.com"
        (livroId, _) <- livroComExemplar False
        reservaId <- reservar socioId livroId
        primeira <- runDB $ cancelarReserva reservaId
        segunda <- runDB $ cancelarReserva reservaId
        assertEq "cancelou" (Right ()) primeira
        assertEq "não cancela de novo" True (either (const True) (const False) segunda)

    it "empréstimo ao próprio sócio atende a reserva; a dos outros continua na fila" $ do
        ana <- novoSocio "ana@example.com"
        bia <- novoSocio "bia@example.com"
        (livroId, exemplarId) <- livroComExemplar False
        reservaAna <- reservar ana livroId
        reservaBia <- reservar bia livroId
        runDB $ update exemplarId [ExemplarDisponivel =. True]
        _ <- runDB $ realizarEmprestimo ana exemplarId dia
        statusAna <- reservaStatus <$> runDB (getJust reservaAna)
        statusBia <- reservaStatus <$> runDB (getJust reservaBia)
        assertEq "Ana atendida" Atendida statusAna
        assertEq "Bia ativa" Ativa statusBia
        fila <- runDB $ filaDeReservas livroId
        assertEq "fila só com Bia" [bia] (map (reservaSocioId . entityVal) fila)
