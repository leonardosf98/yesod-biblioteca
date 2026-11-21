{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
module Model.Tipos where

import ClassyPrelude.Yesod

data EstadoExemplar = Bom | Danificado | Perdido
    deriving (Show, Read, Eq, Ord, Enum, Bounded)
derivePersistField "EstadoExemplar"

data StatusReserva = Ativa | Atendida | Cancelada
    deriving (Show, Read, Eq, Ord, Enum, Bounded)
derivePersistField "StatusReserva"

data Papel = PapelBibliotecario | PapelSocio
    deriving (Show, Read, Eq, Ord, Enum, Bounded)
derivePersistField "Papel"

data StatusPedido = PedidoAguardando | PedidoRetirado | PedidoExpirado | PedidoCancelado
    deriving (Show, Read, Eq, Ord, Enum, Bounded)
derivePersistField "StatusPedido"

estadoTexto :: EstadoExemplar -> Text
estadoTexto Bom = "bom"
estadoTexto Danificado = "danificado"
estadoTexto Perdido = "perdido"

estadoDoTexto :: Text -> Maybe EstadoExemplar
estadoDoTexto t = find ((== t) . estadoTexto) [minBound .. maxBound]
