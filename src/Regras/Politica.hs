{-# LANGUAGE NoImplicitPrelude #-}
module Regras.Politica
    ( prazoDias
    , diasRenovacao
    , limiteAbertos
    , multaPorDiaCentavos
    , prazoRetirada
    , antecedenciaExpiracao
    , validadeSessao
    , validadeCodigoAtivacao
    , maximoTentativas
    , tamanhoMinimoSenha
    ) where

import ClassyPrelude
import Data.Time (NominalDiffTime)

horas :: NominalDiffTime -> NominalDiffTime
horas n = n * 60 * 60

prazoDias :: Integer
prazoDias = 14

diasRenovacao :: Integer
diasRenovacao = 7

limiteAbertos :: Int
limiteAbertos = 3

multaPorDiaCentavos :: Int
multaPorDiaCentavos = 100

prazoRetirada :: NominalDiffTime
prazoRetirada = horas 48

antecedenciaExpiracao :: NominalDiffTime
antecedenciaExpiracao = horas 6

validadeSessao :: NominalDiffTime
validadeSessao = horas (7 * 24)

validadeCodigoAtivacao :: NominalDiffTime
validadeCodigoAtivacao = horas (7 * 24)

maximoTentativas :: Int
maximoTentativas = 5

tamanhoMinimoSenha :: Int
tamanhoMinimoSenha = 8
