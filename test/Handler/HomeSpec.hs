{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.HomeSpec (spec) where

import TestImport

spec :: Spec
spec = withApp $ do
    describe "Página inicial" $ do
        it "carrega e mostra o nome da biblioteca" $ do
            get HomeR
            statusIs 200
            htmlAnyContain "h1" "Biblioteca Comunitária"
