{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.CadastrosSpec (spec) where

import ApiTeste
import Data.Aeson (Value, encode, object, (.=))
import TestImport
import Regras.Conta (salvarBibliotecario)
import Yesod.Auth.HashDB (setPassword)

bibliotecario :: YesodExample App Text
bibliotecario = do
    _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
    entrarNaApi "maria" "senha-forte-123"
    tokenDaResposta

enviar :: ByteString -> Text -> Route App -> Value -> YesodExample App ()
enviar metodo t rota corpo = request $ do
    setMethod metodo
    setUrl rota
    addRequestHeader ("Accept", "application/json")
    addRequestHeader ("Content-Type", "application/json")
    addRequestHeader ("Authorization", "Bearer " <> encodeUtf8 t)
    setRequestBody (encode corpo)

spec :: Spec
spec = withApp $ describe "API de cadastros simples" $ do
    it "cria, lista, edita e exclui autor" $ do
        t <- bibliotecario
        enviarJson (Just t) AutoresR (object ["nome" .= ("  Clarice Lispector " :: Text), "nacionalidade" .= ("" :: Text)])
        statusIs 201
        autorId <- idDaResposta
        autor <- runDB $ getJust autorId
        assertEq "nome sem espaços" "Clarice Lispector" (autorNome autor)
        assertEq "nacionalidade vazia vira nula" Nothing (autorNacionalidade autor)
        enviar "PUT" t (AutorR autorId) (object ["nome" .= ("Clarice" :: Text), "nacionalidade" .= ("Brasileira" :: Text)])
        statusIs 200
        comToken Nothing AutoresR "GET"
        statusIs 200
        bodyContains "\"nacionalidade\":\"Brasileira\""
        comToken (Just t) (AutorR autorId) "DELETE"
        statusIs 204

    it "valida os campos e diz qual está errado" $ do
        t <- bibliotecario
        enviarJson (Just t) AutoresR (object ["nome" .= ("" :: Text), "nacionalidade" .= (replicate 61 'x' :: Text)])
        statusIs 400
        bodyContains "\"nome\":\"Não pode ficar em branco.\""
        bodyContains "\"nacionalidade\":\"Use no máximo 60 caracteres.\""

    it "não exclui autor, editora ou categoria com livros" $ do
        t <- bibliotecario
        (autorId, editoraId, categoriaId) <- runDB $ do
            a <- insert $ Autor "Machado de Assis" Nothing
            e <- insert $ Editora "Garnier" Nothing
            c <- insert $ Categoria "Romance" Nothing
            l <- insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing (Just e) c
            insert_ $ LivroAutor l a
            return (a, e, c)
        comToken (Just t) (AutorR autorId) "DELETE"
        statusIs 409
        comToken (Just t) (EditoraR editoraId) "DELETE"
        statusIs 409
        bodyContains "1 livro(s)"
        comToken (Just t) (CategoriaR categoriaId) "DELETE"
        statusIs 409
        comToken Nothing CategoriasR "GET"
        bodyContains "\"livros\":1"

    it "recusa editora e categoria com nome repetido" $ do
        t <- bibliotecario
        enviarJson (Just t) EditorasR (object ["nome" .= ("Garnier" :: Text)])
        statusIs 201
        enviarJson (Just t) EditorasR (object ["nome" .= ("Garnier" :: Text)])
        statusIs 409
        enviarJson (Just t) CategoriasR (object ["nome" .= ("Poesia" :: Text)])
        statusIs 201
        categoriaId <- idDaResposta
        enviar "PUT" t (CategoriaR categoriaId) (object ["nome" .= ("Poesia" :: Text), "descricao" .= ("Versos" :: Text)])
        statusIs 200
        enviarJson (Just t) CategoriasR (object ["nome" .= ("Poesia" :: Text)])
        statusIs 409

    it "só bibliotecário altera cadastros" $ do
        enviarJson Nothing AutoresR (object ["nome" .= ("X" :: Text)])
        statusIs 401
        runDB $ do
            socioId <- insert $ Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
            usuario <- setPassword "senha-socio-1" (User "ana@example.com" Nothing PapelSocio (Just socioId))
            insert_ usuario
        entrarNaApi "ana@example.com" "senha-socio-1"
        t <- tokenDaResposta
        enviarJson (Just t) CategoriasR (object ["nome" .= ("Y" :: Text)])
        statusIs 403
