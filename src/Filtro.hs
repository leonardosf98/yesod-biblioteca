{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Filtro (contem) where

import ClassyPrelude.Yesod

contem :: EntityField registro Text -> Text -> Filter registro
contem campo texto = Filter campo (FilterValue ("%" <> texto <> "%")) (BackendSpecificFilter "ILIKE")
