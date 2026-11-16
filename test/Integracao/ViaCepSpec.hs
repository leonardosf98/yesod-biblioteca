{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Integracao.ViaCepSpec (spec) where

import Data.Aeson (decode)
import Integracao.ViaCep
import TestImport

interpretar :: LByteString -> Either Text Endereco
interpretar corpo = maybe (Left "json inválido") interpretarCep (decode corpo)

spec :: Spec
spec = describe "interpretarCep" $ do
    it "lê logradouro, bairro, cidade e UF" $
        interpretar "{\"cep\": \"01001-000\", \"logradouro\": \"Praca da Se\", \"bairro\": \"Se\", \"localidade\": \"Sao Paulo\", \"uf\": \"SP\"}"
            `shouldBe` Right (Endereco (Just "Praca da Se") (Just "Se") "Sao Paulo" "SP")

    it "trata CEP de cidade inteira, sem logradouro nem bairro" $
        interpretar "{\"cep\": \"13560-970\", \"logradouro\": \"\", \"bairro\": \"\", \"localidade\": \"Sao Carlos\", \"uf\": \"SP\"}"
            `shouldBe` Right (Endereco Nothing Nothing "Sao Carlos" "SP")

    it "reconhece CEP inexistente com erro em texto" $
        interpretar "{\"erro\": \"true\"}" `shouldBe` Left "CEP não encontrado."

    it "reconhece CEP inexistente com erro booleano" $
        interpretar "{\"erro\": true}" `shouldBe` Left "CEP não encontrado."

    it "recusa resposta sem cidade" $
        interpretar "{\"uf\": \"SP\"}" `shouldBe` Left "Resposta inesperada do ViaCEP."
