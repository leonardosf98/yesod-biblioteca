{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.ApiBalcao
    ( getApiPainelR
    , getApiExemplarCodigoR
    , postApiEmprestimosR
    , postApiDevolucaoR
    , getApiSociosR
    ) where

import Import
import Filtro (contem)
import Control.Monad (mfilter)
import Data.Aeson (withObject)
import Data.Time (diffDays)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Regras.Emprestimo
import Regras.Pedido (expirarPedidos, pendencias)

data Nomes = Nomes
    { nomesSocios :: Map SocioId Text
    , nomesExemplares :: Map ExemplarId Exemplar
    , nomesLivros :: Map LivroId Livro
    }

carregarNomes :: MonadIO m => [SocioId] -> [ExemplarId] -> ReaderT SqlBackend m Nomes
carregarNomes socios exemplares = do
    ss <- selectList [SocioId <-. socios] []
    es <- selectList [ExemplarId <-. exemplares] []
    ls <- selectList [LivroId <-. map (exemplarLivroId . entityVal) es] []
    return $ Nomes
        (Map.fromList [(k, socioNome v) | Entity k v <- ss])
        (Map.fromList [(k, v) | Entity k v <- es])
        (Map.fromList [(k, v) | Entity k v <- ls])

socioJson :: Nomes -> SocioId -> Value
socioJson n k = object ["id" .= k, "nome" .= Map.findWithDefault "—" k (nomesSocios n)]

livroJson :: Nomes -> ExemplarId -> Value
livroJson n k = case Map.lookup k (nomesExemplares n) of
    Nothing -> object []
    Just e -> object
        [ "id" .= exemplarLivroId e
        , "titulo" .= maybe "—" livroTitulo (Map.lookup (exemplarLivroId e) (nomesLivros n))
        , "capaUrl" .= (Map.lookup (exemplarLivroId e) (nomesLivros n) >>= livroCapaUrl)
        ]

codigoDe :: Nomes -> ExemplarId -> Maybe Text
codigoDe n k = exemplarCodigo <$> Map.lookup k (nomesExemplares n)

getApiPainelR :: Handler Value
getApiPainelR = do
    agora <- liftIO getCurrentTime
    dia <- hoje
    (abertos, exemplares, pedidos, nomes) <- runDB $ do
        expirarPedidos agora
        abertos <- selectList [EmprestimoDataDevolucao ==. Nothing] [Asc EmprestimoDataPrevista]
        exemplares <- count [ExemplarEstado !=. Perdido]
        pedidos <- selectList [PedidoStatus ==. PedidoAguardando] [Asc PedidoCriadoEm]
        let emprestimos = map entityVal abertos
            ps = map entityVal pedidos
        nomes <- carregarNomes (map emprestimoSocioId emprestimos ++ map pedidoSocioId ps)
                               (map emprestimoExemplarId emprestimos ++ map pedidoExemplarId ps)
        return (abertos, exemplares, pedidos, nomes)
    let atrasados = [x | x@(Entity _ e) <- abertos, emprestimoDataPrevista e < dia]
        deHoje = [x | x@(Entity _ e) <- abertos, emprestimoDataPrevista e == dia]
        multa e = calcularMulta (emprestimoDataPrevista e) dia
        emprestimoJson (Entity k e) = object
            [ "emprestimoId" .= k
            , "socio" .= socioJson nomes (emprestimoSocioId e)
            , "livro" .= livroJson nomes (emprestimoExemplarId e)
            , "exemplar" .= codigoDe nomes (emprestimoExemplarId e)
            , "dataPrevista" .= emprestimoDataPrevista e
            , "diasAtraso" .= max 0 (diffDays dia (emprestimoDataPrevista e))
            , "multaCentavos" .= multa e
            ]
    returnJson $ object
        [ "resumo" .= object
            [ "abertos" .= length abertos
            , "exemplares" .= exemplares
            , "pedidos" .= length pedidos
            , "atrasados" .= length atrasados
            , "multaAtrasadosCentavos" .= sum (map (multa . entityVal) atrasados)
            , "devolucoesHoje" .= length deHoje
            ]
        , "pedidos" .=
            [ object
                [ "id" .= k
                , "codigo" .= pedidoCodigo p
                , "socio" .= socioJson nomes (pedidoSocioId p)
                , "livro" .= livroJson nomes (pedidoExemplarId p)
                , "exemplar" .= codigoDe nomes (pedidoExemplarId p)
                , "criadoEm" .= pedidoCriadoEm p
                , "limiteRetirada" .= pedidoLimiteRetirada p
                ]
            | Entity k p <- pedidos
            ]
        , "atrasados" .= map emprestimoJson (sortOn (emprestimoDataPrevista . entityVal) atrasados)
        , "devolucoesHoje" .= map emprestimoJson deHoje
        ]

getApiExemplarCodigoR :: Text -> Handler Value
getApiExemplarCodigoR codigo = do
    dia <- hoje
    encontrado <- runDB $ getBy (UniqueCodigo (T.toUpper (T.strip codigo)))
    Entity exemplarId exemplar <- maybe notFound return encontrado
    (livro, aberto, nomes) <- runDB $ do
        livro <- get (exemplarLivroId exemplar)
        aberto <- selectFirst [EmprestimoExemplarId ==. exemplarId, EmprestimoDataDevolucao ==. Nothing] []
        nomes <- carregarNomes (maybe [] (pure . emprestimoSocioId . entityVal) aberto) [exemplarId]
        return (livro, aberto, nomes)
    let emprestimoJson (Entity k e) = object
            [ "id" .= k
            , "socio" .= socioJson nomes (emprestimoSocioId e)
            , "dataPrevista" .= emprestimoDataPrevista e
            , "multaCentavos" .= calcularMulta (emprestimoDataPrevista e) dia
            ]
    returnJson $ object
        [ "exemplar" .= object
            [ "id" .= exemplarId
            , "codigo" .= exemplarCodigo exemplar
            , "estado" .= toLower (tshow (exemplarEstado exemplar))
            , "disponivel" .= exemplarDisponivel exemplar
            ]
        , "livro" .= object ["id" .= exemplarLivroId exemplar, "titulo" .= (livroTitulo <$> livro), "capaUrl" .= (livro >>= livroCapaUrl)]
        , "emprestimo" .= fmap emprestimoJson aberto
        ]

data NovoEmprestimo = NovoEmprestimo SocioId ExemplarId

instance FromJSON NovoEmprestimo where
    parseJSON = withObject "NovoEmprestimo" $ \o ->
        NovoEmprestimo <$> o .: "socioId" <*> o .: "exemplarId"

postApiEmprestimosR :: Handler Value
postApiEmprestimosR = do
    NovoEmprestimo socioId exemplarId <- requireCheckJsonBody
    dia <- hoje
    resultado <- runDB $ do
        bloqueios <- pendencias socioId dia
        case bloqueios of
            b : _ -> return (Left b)
            [] -> realizarEmprestimo socioId exemplarId dia
    case resultado of
        Left motivo -> sendStatusJSON status409 $ object ["erro" .= motivo]
        Right emprestimoId -> do
            emprestimo <- runDB $ getJust emprestimoId
            sendStatusJSON status201 $ object ["id" .= emprestimoId, "dataPrevista" .= emprestimoDataPrevista emprestimo]

postApiDevolucaoR :: EmprestimoId -> Handler Value
postApiDevolucaoR emprestimoId = do
    dia <- hoje
    resultado <- runDB $ registrarDevolucao emprestimoId dia
    case resultado of
        Left motivo -> sendStatusJSON status409 $ object ["erro" .= motivo]
        Right multa -> returnJson $ object ["multaCentavos" .= multa]

getApiSociosR :: Handler Value
getApiSociosR = do
    busca <- mfilter (not . null) . fmap T.strip <$> lookupGetParam "busca"
    dia <- hoje
    resultado <- runDB $ do
        let filtro = case busca of
                Nothing -> []
                Just texto -> [contem SocioNome texto] ||. [contem SocioEmail texto]
        socios <- selectList filtro [Asc SocioNome, LimitTo 20]
        forM socios $ \(Entity k s) -> do
            abertos <- count [EmprestimoSocioId ==. k, EmprestimoDataDevolucao ==. Nothing]
            aguardando <- count [PedidoSocioId ==. k, PedidoStatus ==. PedidoAguardando]
            bloqueios <- pendencias k dia
            conta <- exists [UserSocioId ==. Just k]
            return $ object
                [ "id" .= k
                , "nome" .= socioNome s
                , "email" .= socioEmail s
                , "cidade" .= socioCidade s
                , "emUso" .= (abertos + aguardando)
                , "pendencias" .= bloqueios
                , "contaAtiva" .= conta
                ]
    returnJson $ object ["socios" .= resultado, "limite" .= limiteAbertos]

