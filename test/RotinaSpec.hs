{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module RotinaSpec (spec) where

import Data.Time (addDays, addUTCTime)
import Regras.Comum (hoje)
import Rotina (rodarRotinaEm)
import TestImport

data Cenario = Cenario
    { socio :: SocioId
    , exemplar :: ExemplarId
    , categoria :: CategoriaId
    }

cenario :: YesodExample App Cenario
cenario = runDB $ do
    socioId <- insert $ Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
    insert_ $ User "ana@example.com" Nothing PapelSocio (Just socioId)
    categoriaId <- insert $ Categoria "Romance" Nothing
    livroId <- insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing Nothing categoriaId
    exemplarId <- insert $ Exemplar livroId "DC-1" Bom False
    return (Cenario socioId exemplarId categoriaId)

emprestar :: Cenario -> Day -> Day -> YesodExample App EmprestimoId
emprestar c dia prevista = runDB $ insert $ Emprestimo (exemplar c) (socio c) (addDays (-14) dia) prevista Nothing 0 0 Nothing

avisos :: YesodExample App [Notificacao]
avisos = runDB $ map entityVal <$> selectList [] [Asc NotificacaoId]

spec :: Spec
spec = withApp $ describe "Rotina" $ do
    it "avisa devolução de amanhã, atraso e pedido perto de expirar, sem repetir" $ do
        c <- cenario
        dia <- hoje
        agora <- liftIO getCurrentTime
        _ <- emprestar c dia (addDays 1 dia)
        runDB $ do
            outro <- insert $ Livro "Quincas Borba" Nothing Nothing Nothing Nothing Nothing (categoria c)
            e <- insert $ Exemplar outro "QB-1" Bom False
            insert_ $ Emprestimo e (socio c) (addDays (-20) dia) (addDays (-3) dia) Nothing 0 0 Nothing
            terceiro <- insert $ Livro "Helena" Nothing Nothing Nothing Nothing Nothing (categoria c)
            e3 <- insert $ Exemplar terceiro "HE-1" Bom False
            insert_ $ Pedido e3 (socio c) "AB-CDEF" agora (addUTCTime (2 * 60 * 60) agora) PedidoAguardando Nothing
        novas <- runDB $ rodarRotinaEm agora dia
        assertEq "três avisos" 3 novas
        tipos <- sort . map notificacaoTipo <$> avisos
        assertEq "tipos" ["devolucao_vencendo", "emprestimo_atrasado", "pedido_expirando"] tipos
        atraso <- filter ((== "emprestimo_atrasado") . notificacaoTipo) <$> avisos
        assertEq "multa prevista no texto" True (any (isInfixOf "R$ 3,00" . notificacaoTexto) atraso)
        repetidas <- runDB $ rodarRotinaEm agora dia
        assertEq "segunda passada não repete" 0 repetidas

    it "atraso volta a avisar no dia seguinte, com a multa atualizada" $ do
        c <- cenario
        dia <- hoje
        agora <- liftIO getCurrentTime
        _ <- emprestar c dia (addDays (-1) dia)
        primeiro <- runDB $ rodarRotinaEm agora dia
        segundo <- runDB $ rodarRotinaEm agora (addDays 1 dia)
        assertEq "um aviso por dia" (1, 1) (primeiro, segundo)
        textos <- map notificacaoTexto <$> avisos
        assertEq "multa do segundo dia" True (any (isInfixOf "R$ 2,00") textos)

    it "expira pedido vencido e entrega o exemplar ao primeiro da fila" $ do
        c <- cenario
        dia <- hoje
        agora <- liftIO getCurrentTime
        naFila <- runDB $ do
            outro <- insert $ Socio "Bia" "bia@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
            insert_ $ User "bia@example.com" Nothing PapelSocio (Just outro)
            livroId <- exemplarLivroId <$> getJust (exemplar c)
            insert_ $ Reserva livroId outro dia Ativa
            insert_ $ Pedido (exemplar c) (socio c) "ZZ-ZZZZ" (addUTCTime (-3 * 24 * 60 * 60) agora) (addUTCTime (-60) agora) PedidoAguardando Nothing
            return outro
        _ <- runDB $ rodarRotinaEm agora dia
        tipos <- map notificacaoTipo <$> avisos
        assertEq "expirado e vez na fila" True ("pedido_expirado" `elem` tipos && "fila_disponivel" `elem` tipos)
        doSegundo <- runDB $ count [PedidoSocioId ==. naFila, PedidoStatus ==. PedidoAguardando]
        assertEq "pedido novo para quem estava na fila" 1 doSegundo
