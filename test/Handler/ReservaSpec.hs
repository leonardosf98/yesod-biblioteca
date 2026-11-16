{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ReservaSpec (spec) where

import Seed (popular)
import TestImport
import Yesod.Core (toPathPiece)

livroPorTitulo :: Text -> YesodExample App LivroId
livroPorTitulo titulo = do
    livros <- runDB $ selectList [LivroTitulo ==. titulo] []
    maybe (error "livro") (return . entityKey) (headMay livros)

socioPorEmail :: Text -> YesodExample App SocioId
socioPorEmail email = runDB (getBy (UniqueSocioEmail email)) >>= maybe (error "sócio") (return . entityKey)

spec :: Spec
spec = withApp $ describe "Reservas pela interface" $ do
    it "cria reserva pelo formulário e lista entre as ativas" $ do
        runDB popular
        livroId <- livroPorTitulo "Fundação"
        socioId <- socioPorEmail "bruno@example.com"
        get ReservaNovaR
        request $ do
            setMethod "POST"
            setUrl ReservasR
            addToken
            byLabelExact "Sócio" (toPathPiece socioId)
            byLabelExact "Livro" (toPathPiece livroId)
        statusIs 303
        get ReservasR
        htmlAnyContain "td a" "Bruno Lima"

    it "cancela reserva pela listagem" $ do
        runDB popular
        reservas <- runDB $ selectList [ReservaStatus ==. Ativa] []
        reservaId <- maybe (error "reserva") (return . entityKey) (headMay reservas)
        get ReservasR
        request $ do
            setMethod "POST"
            setUrl (ReservaCancelarR reservaId)
            addToken_ ".form-cancelar"
        statusIs 303
        status <- reservaStatus <$> runDB (getJust reservaId)
        assertEq "cancelada" Cancelada status

    it "avisa a fila de reservas ao devolver" $ do
        runDB popular
        exemplar <- runDB (getBy (UniqueCodigo "FU-001")) >>= maybe (error "exemplar") return
        abertos <- runDB $ selectList [EmprestimoExemplarId ==. entityKey exemplar, EmprestimoDataDevolucao ==. Nothing] []
        emprestimoId <- maybe (error "empréstimo") (return . entityKey) (headMay abertos)
        get (EmprestimoR emprestimoId)
        request $ do
            setMethod "POST"
            setUrl (EmprestimoDevolverR emprestimoId)
            addToken_ ".form-devolver"
        _ <- followRedirect
        htmlAnyContain ".alert-info" "Primeiro da fila: Ana Souza"
