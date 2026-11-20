{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Api.Validacao
    ( V
    , campo
    , campoTexto
    , texto
    , textoOpcional
    , exigido
    , opcional
    , falha
    , exigirValido
    ) where

import ClassyPrelude.Yesod
import Control.Monad (mfilter)
import Data.Aeson.Key (fromText)
import Data.Aeson.Types (Object, parseMaybe, (.:?))
import qualified Data.Text as T

-- Diferente de Either, o <*> junta os erros dos dois lados: o formulário
-- recebe todos os campos inválidos de uma vez, não só o primeiro.
newtype V a = V (Either [(Text, Text)] a)

instance Functor V where
    fmap f (V r) = V (fmap f r)

instance Applicative V where
    pure = V . Right
    V (Left a) <*> V (Left b) = V (Left (a <> b))
    V (Left a) <*> _ = V (Left a)
    V (Right f) <*> V r = V (fmap f r)

falha :: Text -> Text -> V a
falha nome mensagem = V (Left [(nome, mensagem)])

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

exigido :: Text -> Text -> Maybe a -> V a
exigido nome mensagem = maybe (falha nome mensagem) pure

opcional :: Text -> Text -> (a -> Maybe b) -> Maybe a -> V (Maybe b)
opcional nome mensagem validar = maybe (pure Nothing) (fmap Just . exigido nome mensagem . validar)

exigirValido :: MonadHandler m => V a -> m a
exigirValido (V (Right a)) = return a
exigirValido (V (Left erros)) = sendStatusJSON status400 $ object
    [ "erro" .= ("Confira os campos destacados." :: Text)
    , "campos" .= object [fromText k .= v | (k, v) <- erros]
    ]
