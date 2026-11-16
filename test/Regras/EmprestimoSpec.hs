{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.EmprestimoSpec (spec) where

import Data.Time (addDays, fromGregorian)
import Regras.Emprestimo
import TestImport

data Base = Base
    { baseSocio :: SocioId
    , baseLivro :: LivroId
    }

criarBase :: YesodExample App Base
criarBase = runDB $ do
    socioId <- insert (Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing)
    categoriaId <- insert (Categoria "Romance" Nothing)
    livroId <- insert (Livro "Livro" Nothing Nothing Nothing Nothing Nothing categoriaId)
    return (Base socioId livroId)

novoExemplar :: Base -> Text -> EstadoExemplar -> YesodExample App ExemplarId
novoExemplar base codigo estado = runDB $ insert (Exemplar (baseLivro base) codigo estado True)

emprestar :: Base -> ExemplarId -> YesodExample App EmprestimoId
emprestar base exemplarId = do
    resultado <- runDB $ realizarEmprestimo (baseSocio base) exemplarId dia
    either (error . unpack) return resultado

dia :: Day
dia = fromGregorian 2026 11 2

spec :: Spec
spec = do
    describe "calcularMulta" $ do
        it "é zero no prazo ou antes dele" $ do
            calcularMulta dia dia `shouldBe` 0
            calcularMulta dia (addDays (-3) dia) `shouldBe` 0

        it "cobra R$ 1,00 por dia de atraso" $
            calcularMulta dia (addDays 5 dia) `shouldBe` 500

    describe "formatarCentavos" $
        it "formata em reais com duas casas" $ do
            formatarCentavos 0 `shouldBe` "R$ 0,00"
            formatarCentavos 1505 `shouldBe` "R$ 15,05"

    withApp $ describe "regras de empréstimo" $ do
        it "empresta, define o prazo de 14 dias e deixa o exemplar indisponível" $ do
            base <- criarBase
            exemplarId <- novoExemplar base "A-1" Bom
            emprestimoId <- emprestar base exemplarId
            emprestimo <- runDB $ getJust emprestimoId
            assertEq "prazo" (addDays 14 dia) (emprestimoDataPrevista emprestimo)
            exemplar <- runDB $ getJust exemplarId
            assertEq "indisponível" False (exemplarDisponivel exemplar)

        it "não empresta o mesmo exemplar duas vezes" $ do
            base <- criarBase
            exemplarId <- novoExemplar base "A-1" Bom
            _ <- runDB $ realizarEmprestimo (baseSocio base) exemplarId dia
            segundo <- runDB $ realizarEmprestimo (baseSocio base) exemplarId dia
            assertEq "recusado" (Left "Exemplar indisponível.") segundo

        it "não empresta exemplar perdido" $ do
            base <- criarBase
            exemplarId <- novoExemplar base "A-1" Perdido
            resultado <- runDB $ realizarEmprestimo (baseSocio base) exemplarId dia
            assertEq "recusado" (Left "Exemplar marcado como perdido.") resultado

        it "respeita o limite de 3 empréstimos abertos por sócio" $ do
            base <- criarBase
            exemplares <- mapM (\c -> novoExemplar base c Bom) ["A-1", "A-2", "A-3", "A-4"]
            resultados <- runDB $ mapM (\e -> realizarEmprestimo (baseSocio base) e dia) exemplares
            assertEq "três aceitos" 3 (length (rights resultados))
            assertEq "quarto recusado" (Just "O sócio já tem 3 empréstimos em aberto (limite 3).") (headMay [erro | Left erro <- resultados])

        it "devolução com atraso grava a multa e libera o exemplar" $ do
            base <- criarBase
            exemplarId <- novoExemplar base "A-1" Bom
            emprestimoId <- emprestar base exemplarId
            multa <- runDB $ registrarDevolucao emprestimoId (addDays 17 dia)
            assertEq "3 dias de atraso" (Right 300) multa
            emprestimo <- runDB $ getJust emprestimoId
            assertEq "multa gravada" 300 (emprestimoMultaCentavos emprestimo)
            exemplar <- runDB $ getJust exemplarId
            assertEq "disponível de novo" True (exemplarDisponivel exemplar)

        it "não devolve duas vezes" $ do
            base <- criarBase
            exemplarId <- novoExemplar base "A-1" Bom
            emprestimoId <- emprestar base exemplarId
            _ <- runDB $ registrarDevolucao emprestimoId dia
            segunda <- runDB $ registrarDevolucao emprestimoId dia
            assertEq "recusada" (Left "Esse empréstimo já foi devolvido.") segunda

        it "excluir empréstimo aberto libera o exemplar; devolvido não pode ser excluído" $ do
            base <- criarBase
            exemplarId <- novoExemplar base "A-1" Bom
            aberto <- emprestar base exemplarId
            cancelado <- runDB $ cancelarEmprestimo aberto
            assertEq "cancelado" (Right ()) cancelado
            exemplar <- runDB $ getJust exemplarId
            assertEq "liberado" True (exemplarDisponivel exemplar)
            devolvido <- emprestar base exemplarId
            _ <- runDB $ registrarDevolucao devolvido dia
            recusado <- runDB $ cancelarEmprestimo devolvido
            assertEq "histórico mantido" True (either (const True) (const False) recusado)
