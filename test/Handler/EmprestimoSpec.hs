{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.EmprestimoSpec (spec) where

import Seed (popular)
import TestImport
import Yesod.Core (toPathPiece)

porCodigo :: Text -> YesodExample App (Entity Exemplar)
porCodigo codigo = runDB (getBy (UniqueCodigo codigo)) >>= maybe (error "exemplar") return

porEmail :: Text -> YesodExample App (Entity Socio)
porEmail email = runDB (getBy (UniqueSocioEmail email)) >>= maybe (error "sócio") return

emprestimoAberto :: ExemplarId -> YesodExample App (Entity Emprestimo)
emprestimoAberto exemplarId = do
    abertos <- runDB $ selectList [EmprestimoExemplarId ==. exemplarId, EmprestimoDataDevolucao ==. Nothing] []
    maybe (error "sem empréstimo aberto") return (headMay abertos)

spec :: Spec
spec = withApp $ do
    describe "Empréstimos pela interface" $ do
        it "registra empréstimo pelo formulário" $ do
            entrar
            runDB popular
            Entity exemplarId _ <- porCodigo "ER-001"
            Entity socioId _ <- porEmail "ana@example.com"
            get EmprestimoNovoR
            statusIs 200
            request $ do
                setMethod "POST"
                setUrl EmprestimosR
                addToken
                byLabelExact "Sócio" (toPathPiece socioId)
                byLabelExact "Exemplar" (toPathPiece exemplarId)
            statusIs 303
            Entity _ emprestimo <- emprestimoAberto exemplarId
            assertEq "sócio certo" socioId (emprestimoSocioId emprestimo)

        it "não oferece exemplar emprestado no formulário" $ do
            entrar
            runDB popular
            get EmprestimoNovoR
            htmlNoneContain "option" "DC-001"
            htmlAnyContain "option" "ER-001"

        it "registra devolução atrasada com multa" $ do
            entrar
            runDB popular
            Entity exemplarId _ <- porCodigo "DC-001"
            Entity emprestimoId _ <- emprestimoAberto exemplarId
            get (EmprestimoR emprestimoId)
            request $ do
                setMethod "POST"
                setUrl (EmprestimoDevolverR emprestimoId)
                addToken_ ".form-devolver"
            statusIs 303
            _ <- followRedirect
            htmlAnyContain ".alert-warning" "Multa: R$ 6,00"
            exemplar <- runDB $ getJust exemplarId
            assertEq "disponível de novo" True (exemplarDisponivel exemplar)

        it "filtra empréstimos atrasados" $ do
            entrar
            runDB popular
            request $ do
                setUrl EmprestimosR
                addGetParam "situacao" "Atrasados"
            statusIs 200
            htmlAnyContain "td a" "Dom Casmurro"
            htmlNoneContain "td a" "Fundação"

        it "prorroga o prazo de um empréstimo aberto" $ do
            entrar
            runDB popular
            Entity exemplarId _ <- porCodigo "FU-001"
            Entity emprestimoId emprestimo <- emprestimoAberto exemplarId
            get (EmprestimoEditarR emprestimoId)
            request $ do
                setMethod "POST"
                setUrl (EmprestimoR emprestimoId)
                addToken
                byLabelExact "Devolver até" "2099-01-31"
            statusIs 303
            atualizado <- runDB $ getJust emprestimoId
            assertEq "prazo mudou" True (emprestimoDataPrevista atualizado /= emprestimoDataPrevista emprestimo)
