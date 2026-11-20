{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.AcervoSpec (spec) where

import ApiTeste
import Data.Aeson (Value, encode, object, (.=))
import TestImport
import Regras.Conta (salvarBibliotecario)

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
spec = withApp $ describe "API do acervo" $ do
    it "cadastra livro com ISBN normalizado e autores, e edita" $ do
        t <- bibliotecario
        (categoria, autor) <- runDB $ (,) <$> insert (Categoria "Romance" Nothing) <*> insert (Autor "Machado de Assis" Nothing)
        enviarJson (Just t) LivrosR $ object
            ["titulo" .= ("Dom Casmurro" :: Text), "isbn" .= ("978-85-359-1066-7" :: Text), "ano" .= (1899 :: Int), "categoriaId" .= categoria, "autores" .= [autor]]
        statusIs 201
        livroId <- idDaResposta
        livro <- runDB $ getJust livroId
        assertEq "isbn só com dígitos" (Just "9788535910667") (livroIsbn livro)
        vinculos <- runDB $ count [LivroAutorLivroId ==. livroId]
        assertEq "autor ligado" 1 vinculos
        enviar "PUT" t (LivroR livroId) $ object ["titulo" .= ("Dom Casmurro (ed. crítica)" :: Text), "categoriaId" .= categoria, "autores" .= ([] :: [AutorId])]
        statusIs 200
        editado <- runDB $ getJust livroId
        assertEq "título novo" "Dom Casmurro (ed. crítica)" (livroTitulo editado)
        assertEq "isbn removido" Nothing (livroIsbn editado)

    it "valida título, ISBN, ano, capa, categoria e autores de uma vez" $ do
        t <- bibliotecario
        enviarJson (Just t) LivrosR $ object
            ["titulo" .= ("" :: Text), "isbn" .= ("123" :: Text), "ano" .= (3000 :: Int), "capaUrl" .= ("javascript:alert(1)" :: Text), "autores" .= [999 :: Int]]
        statusIs 400
        forM_ ["titulo", "isbn", "ano", "capaUrl", "categoriaId", "autores"] $ \c -> bodyContains ("\"" <> c <> "\":")

    it "recusa ISBN repetido e não exclui livro com exemplares" $ do
        t <- bibliotecario
        categoria <- runDB $ insert (Categoria "Romance" Nothing)
        livroId <- runDB $ insert $ Livro "Dom Casmurro" (Just "9788535910667") Nothing Nothing Nothing Nothing categoria
        enviarJson (Just t) LivrosR $ object ["titulo" .= ("Outro" :: Text), "isbn" .= ("9788535910667" :: Text), "categoriaId" .= categoria]
        statusIs 409
        enviarJson (Just t) (LivroExemplaresR livroId) (object ["estado" .= ("bom" :: Text)])
        statusIs 201
        bodyContains "\"codigo\":\"L"
        comToken (Just t) (LivroR livroId) "DELETE"
        statusIs 409

    it "exemplar: código único, estado e exclusão só sem histórico" $ do
        t <- bibliotecario
        categoria <- runDB $ insert (Categoria "Romance" Nothing)
        livroId <- runDB $ insert $ Livro "Dom Casmurro" Nothing Nothing Nothing Nothing Nothing categoria
        enviarJson (Just t) (LivroExemplaresR livroId) (object ["codigo" .= ("dc-1" :: Text), "estado" .= ("bom" :: Text)])
        statusIs 201
        exemplarId <- idDaResposta
        enviarJson (Just t) (LivroExemplaresR livroId) (object ["codigo" .= ("DC-1" :: Text), "estado" .= ("bom" :: Text)])
        statusIs 409
        enviarJson (Just t) (LivroExemplaresR livroId) (object ["estado" .= ("novo" :: Text)])
        statusIs 400
        enviar "PUT" t (ExemplarR exemplarId) (object ["estado" .= ("perdido" :: Text)])
        statusIs 200
        comToken Nothing (LivroR livroId) "GET"
        bodyNotContains "DC-1"
        comToken (Just t) (LivroR livroId) "GET"
        bodyContains "\"estado\":\"perdido\""
        socio <- runDB $ insert $ Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
        runDB $ insert_ $ Emprestimo exemplarId socio (fromGregorian 2026 1 1) (fromGregorian 2026 1 15) (Just (fromGregorian 2026 1 10)) 0 0 Nothing
        comToken (Just t) (ExemplarR exemplarId) "DELETE"
        statusIs 409

    it "importação valida o ISBN e a categoria antes de chamar a Open Library" $ do
        t <- bibliotecario
        enviarJson (Just t) LivroImportacaoR (object ["isbn" .= ("abc" :: Text)])
        statusIs 400
        bodyContains "\"isbn\":"
        bodyContains "\"categoriaId\":"
        categoria <- runDB $ insert (Categoria "Romance" Nothing)
        _ <- runDB $ insert $ Livro "Dom Casmurro" (Just "9788535910667") Nothing Nothing Nothing Nothing categoria
        enviarJson (Just t) LivroImportacaoR (object ["isbn" .= ("978-85-359-1066-7" :: Text), "categoriaId" .= categoria])
        statusIs 409
