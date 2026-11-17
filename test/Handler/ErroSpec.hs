{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ErroSpec (spec) where

import Database.Persist.Sql (toSqlKey)
import Formato (formatarData)
import Seed (popular)
import TestImport

spec :: Spec
spec = do
    describe "formatarData" $
        it "usa dia/mês/ano" $
            formatarData (fromGregorian 2026 3 7) `shouldBe` "07/03/2026"

    withApp $ describe "Páginas de erro e datas" $ do
        it "mostra página 404 em português para endereço inexistente" $ do
            get ("/nao-existe" :: Text)
            statusIs 404
            htmlAnyContain "h1" "Página não encontrada"

        it "mostra 404 para registro inexistente sem quebrar o breadcrumb" $ do
            get (AutorR (toSqlKey 999999))
            statusIs 404
            htmlAnyContain "h1" "Página não encontrada"

        it "mostra as datas dos empréstimos como dd/mm/aaaa" $ do
            entrar
            runDB popular
            emprestimos <- runDB $ selectList [] []
            primeira <- maybe (error "sem empréstimos") (return . emprestimoDataEmprestimo . entityVal) (headMay emprestimos)
            request $ do
                setUrl EmprestimosR
                addGetParam "situacao" "Todos"
            htmlAnyContain "td" (unpack (formatarData primeira))
