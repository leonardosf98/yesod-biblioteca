{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Handler.Reserva where

import qualified Data.Map.Strict as Map
import Form.Comum
import Import
import Regras.Emprestimo (hoje)
import Regras.Reserva

reservaForm :: Form (SocioId, LivroId)
reservaForm = renderizar $ (,)
    <$> areq (selectField (optionsPersistKey [] [Asc SocioNome] socioNome)) "Sócio" Nothing
    <*> areq (selectField (optionsPersistKey [] [Asc LivroTitulo] livroTitulo)) "Livro" Nothing

getReservasR :: Handler Html
getReservasR = do
    apenasAtivas <- (/= Just "todas") <$> lookupGetParam "status"
    (reservas, socios, livros) <- runDB $ do
        reservas <- selectList [ReservaStatus ==. Ativa | apenasAtivas] [Asc ReservaDataReserva, Asc ReservaId]
        socios <- selectList [SocioId <-. map (reservaSocioId . entityVal) reservas] []
        livros <- selectList [LivroId <-. map (reservaLivroId . entityVal) reservas] []
        return (reservas, socios, livros)
    let nomes = Map.fromList [(k, socioNome v) | Entity k v <- socios]
        titulos = Map.fromList [(k, livroTitulo v) | Entity k v <- livros]
        nomeSocio k = fromMaybe "—" (lookup k nomes)
        tituloLivro k = fromMaybe "—" (lookup k titulos)
    token <- reqToken <$> getRequest
    defaultLayout $ do
        setTitle "Reservas"
        $(widgetFile "reservas/lista")

getReservaNovaR :: Handler Html
getReservaNovaR = do
    (formulario, enctype) <- generateFormPost reservaForm
    paginaFormulario "Nova reserva" ReservasR formulario enctype

postReservasR :: Handler Html
postReservasR = do
    ((resultado, formulario), enctype) <- runFormPost reservaForm
    let reexibir = paginaFormulario "Nova reserva" ReservasR formulario enctype
    case resultado of
        FormSuccess (socioId, livroId) -> do
            dia <- hoje
            criada <- runDB $ criarReserva socioId livroId dia
            case criada of
                Left erro -> mensagem "danger" erro >> reexibir
                Right _ -> mensagem "success" "Reserva registrada." >> redirect ReservasR
        _ -> reexibir

postReservaCancelarR :: ReservaId -> Handler Html
postReservaCancelarR reservaId = do
    _ <- runDB $ get404 reservaId
    cancelada <- runDB $ cancelarReserva reservaId
    either (mensagem "danger") (const (mensagem "success" "Reserva cancelada.")) cancelada
    redirect ReservasR
