{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiCatalogoSpec (spec) where

import ApiTeste
import Data.Aeson (Value, withObject, (.:))
import Data.Aeson.Types (Parser, parseMaybe)
import TestImport
import Yesod.Core (toPathPiece)

data Acervo = Acervo
    { domCasmurro :: LivroId
    , vidasSecas :: LivroId
    , romance :: CategoriaId
    }

montarAcervo :: YesodExample App Acervo
montarAcervo = runDB $ do
    categoriaRomance <- insert $ Categoria "Romance" Nothing
    classicos <- insert $ Categoria "Clássicos" Nothing
    machado <- insert $ Autor "Machado de Assis" Nothing
    graciliano <- insert $ Autor "Graciliano Ramos" Nothing
    dom <- insert $ Livro "Dom Casmurro" (Just "9788535910667") (Just 1899) (Just "Bentinho e Capitu.") Nothing Nothing categoriaRomance
    vidas <- insert $ Livro "Vidas Secas" Nothing (Just 1938) Nothing Nothing Nothing classicos
    insert_ $ LivroAutor dom machado
    insert_ $ LivroAutor vidas graciliano
    insert_ $ Exemplar dom "EX-1" Bom True
    insert_ $ Exemplar dom "EX-2" Danificado True
    insert_ $ Exemplar dom "EX-3" Bom False
    insert_ $ Exemplar dom "EX-4" Perdido True
    insert_ $ Exemplar vidas "EX-5" Bom False
    socio <- insert $ Socio "Ana" "ana@example.com" Nothing Nothing Nothing Nothing Nothing Nothing Nothing
    insert_ $ Reserva vidas socio (fromGregorian 2026 11 1) Ativa
    insert_ $ Reserva vidas socio (fromGregorian 2026 11 2) Cancelada
    return (Acervo dom vidas categoriaRomance)

listar :: [(Text, Text)] -> YesodExample App [(Text, Int, Int, [Text])]
listar parametros = do
    request $ do
        setMethod "GET"
        setUrl ApiLivrosR
        addRequestHeader ("Accept", "application/json")
        forM_ parametros (uncurry addGetParam)
    statusIs 200
    fromMaybe [] . parseMaybe lerLivros <$> respostaJson
  where
    lerLivros :: Value -> Parser [(Text, Int, Int, [Text])]
    lerLivros = withObject "catalogo" $ \o -> o .: "livros" >>= mapM (withObject "livro" $ \l ->
        (,,,) <$> l .: "titulo" <*> l .: "disponiveis" <*> l .: "fila" <*> l .: "autores")

spec :: Spec
spec = withApp $ describe "API do catálogo" $ do
    it "lista os livros com autores, disponíveis e fila, sem login" $ do
        _ <- montarAcervo
        livros <- listar []
        assertEq "livros"
            [ ("Dom Casmurro", 2, 0, ["Machado de Assis"])
            , ("Vidas Secas", 0, 1, ["Graciliano Ramos"])
            ] livros
        bodyContains "\"categorias\""

    it "busca por título, autor ou ISBN, sem diferenciar maiúsculas" $ do
        _ <- montarAcervo
        porTitulo <- listar [("busca", "casmurro")]
        assertEq "título" ["Dom Casmurro"] (map (\(t, _, _, _) -> t) porTitulo)
        porAutor <- listar [("busca", "graciliano")]
        assertEq "autor" ["Vidas Secas"] (map (\(t, _, _, _) -> t) porAutor)
        porIsbn <- listar [("busca", "9788535910667")]
        assertEq "isbn" ["Dom Casmurro"] (map (\(t, _, _, _) -> t) porIsbn)

    it "filtra por categoria" $ do
        acervo <- montarAcervo
        livros <- listar [("categoria", toPathPiece (romance acervo))]
        assertEq "só romance" ["Dom Casmurro"] (map (\(t, _, _, _) -> t) livros)

    it "pagina o catálogo e informa o total" $ do
        _ <- montarAcervo
        primeira <- listar [("porPagina", "1")]
        assertEq "primeira página" ["Dom Casmurro"] (map (\(t, _, _, _) -> t) primeira)
        bodyContains "\"total\":2"
        bodyContains "\"paginas\":2"
        segunda <- listar [("porPagina", "1"), ("pagina", "2")]
        assertEq "segunda página" ["Vidas Secas"] (map (\(t, _, _, _) -> t) segunda)
        alem <- listar [("porPagina", "1"), ("pagina", "9")]
        assertEq "página além do fim" [] alem

    it "ignora pagina e porPagina inválidos" $ do
        _ <- montarAcervo
        livros <- listar [("pagina", "abc"), ("porPagina", "0")]
        assertEq "volta para a primeira página" 1 (length livros)
        bodyContains "\"porPagina\":1"

    it "detalhe traz exemplares sem os perdidos" $ do
        acervo <- montarAcervo
        request $ do
            setMethod "GET"
            setUrl (ApiLivroR (domCasmurro acervo))
            addRequestHeader ("Accept", "application/json")
        statusIs 200
        bodyContains "\"sinopse\":\"Bentinho e Capitu.\""
        bodyContains "\"EX-2\""
        bodyContains "\"estado\":\"danificado\""
        bodyNotContains "EX-4"
        bodyContains "\"disponiveis\":2"

    it "detalhe de livro inexistente responde 404 em JSON" $ do
        acervo <- montarAcervo
        runDB $ deleteWhere [ExemplarLivroId ==. vidasSecas acervo] >> deleteWhere [ReservaLivroId ==. vidasSecas acervo] >> delete (vidasSecas acervo)
        request $ do
            setMethod "GET"
            setUrl (ApiLivroR (vidasSecas acervo))
            addRequestHeader ("Accept", "application/json")
        statusIs 404
        bodyContains "\"erro\""
