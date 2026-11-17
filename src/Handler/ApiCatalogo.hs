{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiCatalogo
    ( getApiLivrosR
    , getApiLivroR
    ) where

import Import
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Regras.Pedido (expirarPedidos)
import Control.Monad (mfilter)

data Contagem = Contagem { disponiveis :: Int, fila :: Int }

getApiLivrosR :: Handler Value
getApiLivrosR = do
    busca <- mfilter (not . null) . fmap T.strip <$> lookupGetParam "busca"
    categoriaFiltro <- (>>= fromPathPiece) <$> lookupGetParam "categoria"
    agora <- liftIO getCurrentTime
    (livros, categorias, autoresPorLivro, contagens) <- runDB $ do
        expirarPedidos agora
        porAutor <- case busca of
            Nothing -> return []
            Just texto -> do
                autores <- selectKeysList [contem AutorNome texto] []
                map (livroAutorLivroId . entityVal) <$> selectList [LivroAutorAutorId <-. autores] []
        let filtroBusca = case busca of
                Nothing -> []
                Just texto -> [contem LivroTitulo texto] ||. [LivroIsbn ==. Just texto] ||. [LivroId <-. porAutor]
            filtroCategoria = maybe [] (\c -> [LivroCategoriaId ==. c]) categoriaFiltro
        livros <- selectList (filtroBusca ++ filtroCategoria) [Asc LivroTitulo]
        categorias <- selectList [] [Asc CategoriaNome]
        let ids = map entityKey livros
        autores <- autoresDosLivros ids
        contagens <- contagensDosLivros ids
        return (livros, categorias, autores, contagens)
    let nomeCategoria = Map.fromList [(k, categoriaNome v) | Entity k v <- categorias]
    returnJson $ object
        [ "livros" .=
            [ object
                [ "id" .= livroId
                , "titulo" .= livroTitulo livro
                , "ano" .= livroAno livro
                , "capaUrl" .= livroCapaUrl livro
                , "autores" .= map (autorNome . entityVal) (Map.findWithDefault [] livroId autoresPorLivro)
                , "categoria" .= categoriaJson (livroCategoriaId livro) (Map.lookup (livroCategoriaId livro) nomeCategoria)
                , "disponiveis" .= disponiveis (contagemDe livroId contagens)
                , "fila" .= fila (contagemDe livroId contagens)
                ]
            | Entity livroId livro <- livros
            ]
        , "categorias" .= [categoriaJson k (Just (categoriaNome v)) | Entity k v <- categorias]
        ]

getApiLivroR :: LivroId -> Handler Value
getApiLivroR livroId = do
    agora <- liftIO getCurrentTime
    (livro, autores, editora, categoria, exemplares, contagens) <- runDB $ do
        expirarPedidos agora
        livro <- get404 livroId
        autores <- autoresDosLivros [livroId]
        editora <- maybe (return Nothing) get (livroEditoraId livro)
        categoria <- get (livroCategoriaId livro)
        exemplares <- selectList [ExemplarLivroId ==. livroId] [Asc ExemplarCodigo]
        contagens <- contagensDosLivros [livroId]
        return (livro, autores, editora, categoria, exemplares, contagens)
    let contagem = contagemDe livroId contagens
    returnJson $ object
        [ "id" .= livroId
        , "titulo" .= livroTitulo livro
        , "isbn" .= livroIsbn livro
        , "ano" .= livroAno livro
        , "sinopse" .= livroSinopse livro
        , "capaUrl" .= livroCapaUrl livro
        , "editora" .= (editoraNome <$> editora)
        , "categoria" .= categoriaJson (livroCategoriaId livro) (categoriaNome <$> categoria)
        , "autores" .= [object ["id" .= k, "nome" .= autorNome v] | Entity k v <- Map.findWithDefault [] livroId autores]
        , "exemplares" .=
            [ object
                [ "codigo" .= exemplarCodigo e
                , "estado" .= estadoTexto (exemplarEstado e)
                , "disponivel" .= exemplarDisponivel e
                ]
            | Entity _ e <- exemplares
            , exemplarEstado e /= Perdido
            ]
        , "disponiveis" .= disponiveis contagem
        , "fila" .= fila contagem
        ]

autoresDosLivros :: MonadIO m => [LivroId] -> ReaderT SqlBackend m (Map LivroId [Entity Autor])
autoresDosLivros ids = do
    vinculos <- selectList [LivroAutorLivroId <-. ids] []
    autores <- selectList [AutorId <-. map (livroAutorAutorId . entityVal) vinculos] [Asc AutorNome]
    let porId = Map.fromList [(entityKey a, a) | a <- autores]
    return $ Map.fromListWith (flip (++))
        [ (livroAutorLivroId v, [a])
        | Entity _ v <- vinculos
        , Just a <- [Map.lookup (livroAutorAutorId v) porId]
        ]

contagensDosLivros :: MonadIO m => [LivroId] -> ReaderT SqlBackend m (Map LivroId Contagem)
contagensDosLivros ids = do
    livres <- selectList [ExemplarLivroId <-. ids, ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido] []
    reservas <- selectList [ReservaLivroId <-. ids, ReservaStatus ==. Ativa] []
    let contar chaves = Map.fromListWith (+) [(k, 1 :: Int) | k <- chaves]
        livresPorLivro = contar (map (exemplarLivroId . entityVal) livres)
        filaPorLivro = contar (map (reservaLivroId . entityVal) reservas)
    return $ Map.fromList
        [ (k, Contagem (Map.findWithDefault 0 k livresPorLivro) (Map.findWithDefault 0 k filaPorLivro))
        | k <- ids
        ]

contagemDe :: LivroId -> Map LivroId Contagem -> Contagem
contagemDe = Map.findWithDefault (Contagem 0 0)

categoriaJson :: CategoriaId -> Maybe Text -> Value
categoriaJson k nome = object ["id" .= k, "nome" .= nome]

estadoTexto :: EstadoExemplar -> Text
estadoTexto Bom = "bom"
estadoTexto Danificado = "danificado"
estadoTexto Perdido = "perdido"

contem :: EntityField registro Text -> Text -> Filter registro
contem campo texto = Filter campo (FilterValue ("%" <> texto <> "%")) (BackendSpecificFilter "ILIKE")
