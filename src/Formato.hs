{-# LANGUAGE NoImplicitPrelude #-}
module Formato
    ( formatarData
    ) where

import ClassyPrelude.Yesod

formatarData :: Day -> Text
formatarData = pack . formatTime defaultTimeLocale "%d/%m/%Y"
