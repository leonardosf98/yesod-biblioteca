{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Api.Filtro
    ( contem
    , parametroDeBusca
    , parametroInteiro
    ) where

import Import
import Control.Monad (mfilter)
import qualified Data.Text as T

contem :: EntityField registro Text -> Text -> Filter registro
contem campo texto = Filter campo (FilterValue ("%" <> texto <> "%")) (BackendSpecificFilter "ILIKE")

parametroDeBusca :: Handler (Maybe Text)
parametroDeBusca = mfilter (not . null) . fmap T.strip <$> lookupGetParam "busca"

parametroInteiro :: Text -> Int -> (Int, Int) -> Handler Int
parametroInteiro nome padrao (minimo, maximo) =
    min maximo . max minimo . fromMaybe padrao . (>>= readMay) <$> lookupGetParam nome
