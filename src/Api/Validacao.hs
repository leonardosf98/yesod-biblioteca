{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Api.Validacao
    ( V
    , texto
    , textoOpcional
    , campoTexto
    , campo
    , falha
    , exigirValido
    , conflito
    ) where

import ClassyPrelude.Yesod
import Data.Aeson.Key (fromText)
import Control.Monad (mfilter)
import Data.Aeson.Types (Object, parseMaybe, (.:?))
import qualified Data.Text as T

newtype V a = V (Either [(Text, Text)] a)

instance Functor V where
    fmap f (V r) = V (fmap f r)

instance Applicative V where
    pure = V . Right
    V (Left a) <*> V (Left b) = V (Left (a <> b))
    V (Left a) <*> _ = V (Left a)
    V (Right f) <*> V r = V (fmap f r)

falha :: Text -> Text -> V a
falha nome mensagemErro = V (Left [(nome, mensagemErro)])

campo :: FromJSON a => Object -> Text -> Maybe a
campo o nome = join (parseMaybe (.:? fromText nome) o)

campoTexto :: Object -> Text -> Maybe Text
campoTexto o nome = mfilter (not . null) (T.strip <$> campo o nome)

texto :: Text -> Int -> Maybe Text -> V Text
texto nome limite valor = case valor of
    Nothing -> falha nome "Não pode ficar em branco."
    Just t
        | T.length t > limite -> falha nome ("Use no máximo " <> tshow limite <> " caracteres.")
        | otherwise -> pure t

textoOpcional :: Text -> Int -> Maybe Text -> V (Maybe Text)
textoOpcional nome limite = maybe (pure Nothing) (fmap Just . texto nome limite . Just)

exigirValido :: MonadHandler m => V a -> m a
exigirValido (V (Right a)) = return a
exigirValido (V (Left erros)) = sendStatusJSON status400 $ object
    [ "erro" .= ("Confira os campos destacados." :: Text)
    , "campos" .= object [fromText k .= v | (k, v) <- erros]
    ]

conflito :: MonadHandler m => Text -> m a
conflito mensagemErro = sendStatusJSON status409 $ object ["erro" .= mensagemErro]
