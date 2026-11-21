{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.Catalogo
    ( getLivrosR
    , getLivroR
    ) where

import Import
import Api.Filtro
import Api.Relacionados (contarPorChave)
import qualified Data.Map.Strict as Map
import Regras.Pedido (expirarPedidos)

data Contagem = Contagem { disponiveis :: Int, fila :: Int }

data Pagina = Pagina { numeroDaPagina :: Int, porPagina :: Int }

getLivrosR :: Handler Value
getLivrosR = do
    busca <- parametroDeBusca
    categoria <- (>>= fromPathPiece) <$> lookupGetParam "categoria"
    situacao <- lookupGetParam "situacao"
    pagina <- Pagina <$> parametroInteiro "pagina" 1 (1, maxBound) <*> parametroInteiro "porPagina" 24 (1, 100)
    agora <- liftIO getCurrentTime
    (livros, total, categorias, autores, contagens) <- runDB $ do
        expirarPedidos agora
        porBusca <- filtroDeBusca busca
        porSituacao <- filtroDeSituacao situacao
        let filtros = porBusca ++ filtroDeCategoria categoria ++ porSituacao
        total <- count filtros
        livros <- selectList filtros
            [ Asc LivroTitulo, Asc LivroId
            , LimitTo (porPagina pagina), OffsetBy ((numeroDaPagina pagina - 1) * porPagina pagina)
            ]
        categorias <- selectList [] [Asc CategoriaNome]
        let ids = map entityKey livros
        autores <- autoresDosLivros ids
        contagens <- contagensDosLivros ids
        return (livros, total, categorias, autores, contagens)
    let nomeDaCategoria = Map.fromList [(k, categoriaNome v) | Entity k v <- categorias]
        itemJson (Entity livroId livro) = object
            [ "id" .= livroId
            , "titulo" .= livroTitulo livro
            , "ano" .= livroAno livro
            , "capaUrl" .= livroCapaUrl livro
            , "autores" .= map (autorNome . entityVal) (Map.findWithDefault [] livroId autores)
            , "categoria" .= categoriaJson (livroCategoriaId livro) (Map.lookup (livroCategoriaId livro) nomeDaCategoria)
            , "disponiveis" .= disponiveis (contagemDe livroId contagens)
            , "fila" .= fila (contagemDe livroId contagens)
            ]
    returnJson $ object
        [ "livros" .= map itemJson livros
        , "categorias" .= [categoriaJson k (Just (categoriaNome v)) | Entity k v <- categorias]
        , "pagina" .= numeroDaPagina pagina
        , "porPagina" .= porPagina pagina
        , "total" .= total
        , "paginas" .= max 1 ((total + porPagina pagina - 1) `div` porPagina pagina)
        ]

filtroDeBusca :: MonadIO m => Maybe Text -> ReaderT SqlBackend m [Filter Livro]
filtroDeBusca Nothing = return []
filtroDeBusca (Just texto) = do
    autores <- selectKeysList [contem AutorNome texto] []
    doAutor <- map (livroAutorLivroId . entityVal) <$> selectList [LivroAutorAutorId <-. autores] []
    return $ [contem LivroTitulo texto] ||. [LivroIsbn ==. Just texto] ||. [LivroId <-. doAutor]

filtroDeCategoria :: Maybe CategoriaId -> [Filter Livro]
filtroDeCategoria = maybe [] (\c -> [LivroCategoriaId ==. c])

filtroDeSituacao :: MonadIO m => Maybe Text -> ReaderT SqlBackend m [Filter Livro]
filtroDeSituacao situacao = case situacao of
    Just "disponivel" -> (\ids -> [LivroId <-. ids]) <$> livrosComExemplarLivre
    Just "indisponivel" -> (\ids -> [LivroId /<-. ids]) <$> livrosComExemplarLivre
    Just "fila" -> (\ids -> [LivroId <-. ids]) . map (reservaLivroId . entityVal) <$> selectList [ReservaStatus ==. Ativa] []
    _ -> return []

getLivroR :: LivroId -> Handler Value
getLivroR livroId = do
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
    bibliotecario <- maybe False ((== PapelBibliotecario) . userPapel . entityVal) <$> usuarioAtual
    let contagem = contagemDe livroId contagens
        visivel (Entity _ e) = bibliotecario || exemplarEstado e /= Perdido
    returnJson $ object
        [ "id" .= livroId
        , "titulo" .= livroTitulo livro
        , "isbn" .= livroIsbn livro
        , "ano" .= livroAno livro
        , "sinopse" .= livroSinopse livro
        , "capaUrl" .= livroCapaUrl livro
        , "editora" .= (editoraNome <$> editora)
        , "editoraId" .= livroEditoraId livro
        , "categoria" .= categoriaJson (livroCategoriaId livro) (categoriaNome <$> categoria)
        , "autores" .= [object ["id" .= k, "nome" .= autorNome v] | Entity k v <- Map.findWithDefault [] livroId autores]
        , "exemplares" .= map exemplarJson (filter visivel exemplares)
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
    let livresPorLivro = contarPorChave (map (exemplarLivroId . entityVal) livres)
        filaPorLivro = contarPorChave (map (reservaLivroId . entityVal) reservas)
    return $ Map.fromList
        [ (k, Contagem (Map.findWithDefault 0 k livresPorLivro) (Map.findWithDefault 0 k filaPorLivro))
        | k <- ids
        ]

livrosComExemplarLivre :: MonadIO m => ReaderT SqlBackend m [LivroId]
livrosComExemplarLivre =
    map (exemplarLivroId . entityVal)
        <$> selectList [ExemplarDisponivel ==. True, ExemplarEstado !=. Perdido] []

contagemDe :: LivroId -> Map LivroId Contagem -> Contagem
contagemDe = Map.findWithDefault (Contagem 0 0)

categoriaJson :: CategoriaId -> Maybe Text -> Value
categoriaJson k nome = object ["id" .= k, "nome" .= nome]

exemplarJson :: Entity Exemplar -> Value
exemplarJson (Entity k e) = object
    [ "id" .= k
    , "codigo" .= exemplarCodigo e
    , "estado" .= estadoTexto (exemplarEstado e)
    , "disponivel" .= exemplarDisponivel e
    ]
