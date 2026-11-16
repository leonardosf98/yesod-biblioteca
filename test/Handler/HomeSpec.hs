{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.HomeSpec (spec) where

import Seed (popular)
import TestImport

spec :: Spec
spec = withApp $ do
    describe "Página inicial" $ do
        it "carrega e mostra o nome da biblioteca" $ do
            get HomeR
            statusIs 200
            htmlAnyContain "h1" "Biblioteca Comunitária"

        it "mostra os contadores calculados a partir do banco" $ do
            runDB popular
            get HomeR
            statusIs 200
            htmlAllContain ".contador-livros .panel-body" "4"
            htmlAllContain ".contador-disponiveis .panel-body" "3"
            htmlAllContain ".contador-socios .panel-body" "2"
            htmlAllContain ".contador-atrasados .panel-body" "1"
