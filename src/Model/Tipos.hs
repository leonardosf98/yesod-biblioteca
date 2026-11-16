{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell #-}
module Model.Tipos where

import ClassyPrelude.Yesod

data EstadoExemplar = Bom | Danificado | Perdido
    deriving (Show, Read, Eq, Ord, Enum, Bounded)
derivePersistField "EstadoExemplar"

data StatusReserva = Ativa | Atendida | Cancelada
    deriving (Show, Read, Eq, Ord, Enum, Bounded)
derivePersistField "StatusReserva"
