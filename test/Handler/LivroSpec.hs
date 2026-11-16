{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.LivroSpec (spec) where

import Seed (popular)
import TestImport
import Yesod.Core (toPathPiece)

data Base = Base
    { baseCategoria :: CategoriaId
    , baseEditora :: EditoraId
    , baseAutorA :: AutorId
    , baseAutorB :: AutorId
    }

criarBase :: YesodExample App Base
criarBase = runDB $ Base
    <$> insert (Categoria "Romance" Nothing)
    <*> insert (Editora "Rocco" Nothing)
    <*> insert (Autor "Autora A" Nothing)
    <*> insert (Autor "Autor B" Nothing)

enviarLivro :: Route App -> Base -> Text -> Text -> [AutorId] -> YesodExample App ()
enviarLivro rota base titulo isbn autores = request $ do
    setMethod "POST"
    setUrl rota
    addToken
    byLabelExact "Título" titulo
    byLabelExact "ISBN" isbn
    byLabelExact "Ano" ""
    byLabelExact "Sinopse" ""
    byLabelExact "URL da capa" ""
    byLabelExact "Editora" (toPathPiece (baseEditora base))
    byLabelExact "Categoria" (toPathPiece (baseCategoria base))
    mapM_ (byLabelExact "Autores" . toPathPiece) autores

livroPorTitulo :: Text -> YesodExample App (Entity Livro)
livroPorTitulo titulo = do
    livros <- runDB $ selectList [LivroTitulo ==. titulo] []
    case livros of
        [livro] -> return livro
        _ -> error ("esperava um livro chamado " <> unpack titulo)

spec :: Spec
spec = withApp $ do
    describe "CRUD de livro" $ do
        it "cadastra livro com dois autores e normaliza o ISBN" $ do
            base <- criarBase
            get LivroNovoR
            enviarLivro LivrosR base "Livro novo" "123-4567-890" [baseAutorA base, baseAutorB base]
            statusIs 303
            Entity livroId livro <- livroPorTitulo "Livro novo"
            assertEq "ISBN sem hífens" (Just "1234567890") (livroIsbn livro)
            vinculos <- runDB $ count [LivroAutorLivroId ==. livroId]
            assertEq "dois autores" 2 vinculos

        it "recusa ISBN com tamanho errado" $ do
            base <- criarBase
            get LivroNovoR
            enviarLivro LivrosR base "Livro novo" "12345" []
            statusIs 200
            bodyContains "ISBN deve ter 10 ou 13 dígitos"

        it "recusa ISBN repetido mas aceita vários livros sem ISBN" $ do
            base <- criarBase
            get LivroNovoR
            enviarLivro LivrosR base "Primeiro" "1234567890" []
            get LivroNovoR
            enviarLivro LivrosR base "Segundo" "1234567890" []
            statusIs 200
            htmlAnyContain ".alert-danger" "Já existe um livro com esse ISBN."
            get LivroNovoR
            enviarLivro LivrosR base "Sem ISBN 1" "" []
            get LivroNovoR
            enviarLivro LivrosR base "Sem ISBN 2" "" []
            total <- runDB $ count ([] :: [Filter Livro])
            assertEq "três livros gravados" 3 total

        it "troca os autores ao editar" $ do
            base <- criarBase
            get LivroNovoR
            enviarLivro LivrosR base "Livro" "" [baseAutorA base]
            Entity livroId _ <- livroPorTitulo "Livro"
            get (LivroEditarR livroId)
            enviarLivro (LivroR livroId) base "Livro" "" [baseAutorB base]
            statusIs 303
            vinculos <- runDB $ selectList [LivroAutorLivroId ==. livroId] []
            assertEq "só o autor B" [baseAutorB base] (map (livroAutorAutorId . entityVal) vinculos)

        it "exclui livro sem exemplares junto com os vínculos de autor" $ do
            base <- criarBase
            get LivroNovoR
            enviarLivro LivrosR base "Descartável" "" [baseAutorA base]
            Entity livroId _ <- livroPorTitulo "Descartável"
            get (LivroR livroId)
            request $ do
                setMethod "POST"
                setUrl (LivroExcluirR livroId)
                addToken
            statusIs 303
            restante <- runDB $ (+) <$> count [LivroId ==. livroId] <*> count [LivroAutorLivroId ==. livroId]
            assertEq "livro e vínculos removidos" 0 restante

        it "não exclui livro com exemplares" $ do
            runDB popular
            Entity livroId _ <- livroPorTitulo "Dom Casmurro"
            get (LivroR livroId)
            request $ do
                setMethod "POST"
                setUrl (LivroExcluirR livroId)
                addToken
            restante <- runDB $ count [LivroId ==. livroId]
            assertEq "livro mantido" 1 restante

        it "filtra por trecho do título sem diferenciar maiúsculas" $ do
            runDB popular
            request $ do
                setUrl LivrosR
                addGetParam "busca" "dom"
            statusIs 200
            htmlAnyContain "td a" "Dom Casmurro"
            htmlNoneContain "td a" "Fundação"

        it "filtra por categoria" $ do
            runDB popular
            Entity _ fundacao <- livroPorTitulo "Fundação"
            request $ do
                setUrl LivrosR
                addGetParam "categoria" (toPathPiece (livroCategoriaId fundacao))
            htmlAnyContain "td a" "Fundação"
            htmlNoneContain "td a" "Dom Casmurro"
