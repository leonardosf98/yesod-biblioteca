{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE InstanceSigs #-}

module Foundation where

import Import.NoFoundation
import Control.Monad.Logger (LogSource)
import Data.Kind (Type)
import Database.Persist.Sql (ConnectionPool, runSqlPool)
import Token (hashToken)
import Yesod.Core.Types (Logger)
import qualified Yesod.Core.Unsafe as Unsafe

data App = App
    { appSettings    :: AppSettings
    , appConnPool    :: ConnectionPool
    , appHttpManager :: Manager
    , appLogger      :: Logger
    }

mkYesodData "App" $(parseRoutesFile "config/routes.yesodroutes")

type DB a = forall (m :: Type -> Type).
    (MonadUnliftIO m) => ReaderT SqlBackend m a

instance Yesod App where
    approot :: Approot App
    approot = ApprootRequest $ \app req ->
        case appRoot $ appSettings app of
            Nothing -> getApprootText guessApproot app req
            Just root -> root

    -- A API só aceita o token no cabeçalho Authorization; sem cookie de sessão não há CSRF a proteger.
    makeSessionBackend :: App -> IO (Maybe SessionBackend)
    makeSessionBackend _ = return Nothing

    isAuthorized :: Route App -> Bool -> Handler AuthResult
    isAuthorized rota escrita = verificarAcesso (acessoDa rota escrita)

    shouldLogIO :: App -> LogSource -> LogLevel -> IO Bool
    shouldLogIO app _source level =
        return $
        appShouldLogAll (appSettings app)
            || level == LevelWarn
            || level == LevelError

    makeLogger :: App -> IO Logger
    makeLogger = return . appLogger

    errorHandler :: ErrorResponse -> Handler TypedContent
    errorHandler resposta = return $ toTypedContent $ object ["erro" .= mensagemErro]
      where
        mensagemErro :: Text
        mensagemErro = case resposta of
            NotFound -> "Recurso não encontrado."
            InternalError _ -> "Erro inesperado no servidor."
            InvalidArgs _ -> "Corpo da requisição inválido."
            NotAuthenticated -> "Entre para continuar."
            PermissionDenied motivo -> motivo
            BadMethod _ -> "Método não permitido."

data Acesso = Publico | QualquerUsuario | SomenteSocio | SomenteBibliotecario

acessoDa :: Route App -> Bool -> Acesso
acessoDa rota escrita
    | rotaPublica rota = Publico
    | not escrita && leituraDoCatalogo rota = Publico
    | rota == EuR || rotaDeNotificacao rota = QualquerUsuario
    | rotaDoSocio rota = SomenteSocio
    | otherwise = SomenteBibliotecario

rotaPublica :: Route App -> Bool
rotaPublica rota = case rota of
    HomeR -> True
    FaviconR -> True
    RobotsR -> True
    SessoesR -> True
    AtivacaoR -> True
    _ -> False

leituraDoCatalogo :: Route App -> Bool
leituraDoCatalogo rota = case rota of
    LivrosR -> True
    LivroR _ -> True
    AutoresR -> True
    EditorasR -> True
    CategoriasR -> True
    _ -> False

rotaDeNotificacao :: Route App -> Bool
rotaDeNotificacao rota = case rota of
    NotificacoesR -> True
    NotificacoesLeituraR -> True
    NotificacaoLeituraR _ -> True
    _ -> False

rotaDoSocio :: Route App -> Bool
rotaDoSocio rota = case rota of
    LivroPedidosR _ -> True
    EuPedidoR _ -> True
    EuEmprestimosR -> True
    EuRenovacaoR _ -> True
    LivroReservasR _ -> True
    EuReservaR _ -> True
    _ -> False

verificarAcesso :: Acesso -> Handler AuthResult
verificarAcesso acesso = do
    usuario <- case acesso of
        Publico -> return Nothing
        _ -> usuarioAtual
    return $ case (acesso, entityVal <$> usuario) of
        (Publico, _) -> Authorized
        (_, Nothing) -> AuthenticationRequired
        (QualquerUsuario, Just _) -> Authorized
        (SomenteSocio, Just u)
            | userPapel u == PapelSocio -> Authorized
            | otherwise -> Unauthorized "Acesso restrito a sócios."
        (SomenteBibliotecario, Just u)
            | userPapel u == PapelBibliotecario -> Authorized
            | otherwise -> Unauthorized "Acesso restrito ao bibliotecário."

newtype UsuarioDaRequisicao = UsuarioDaRequisicao (Maybe (Entity User))

usuarioAtual :: Handler (Maybe (Entity User))
usuarioAtual = do
    UsuarioDaRequisicao usuario <- cached $ do
        token <- lookupBearerAuth
        agora <- liftIO getCurrentTime
        fmap UsuarioDaRequisicao $ case token of
            Nothing -> return Nothing
            Just valor -> runDB $ do
                sessao <- getBy (UniqueSessaoToken (hashToken valor))
                case sessao of
                    Just (Entity _ s) | sessaoExpiraEm s > agora -> getEntity (sessaoUserId s)
                    _ -> return Nothing
    return usuario

exigirUsuario :: Handler (Entity User)
exigirUsuario = usuarioAtual >>= maybe notAuthenticated return

instance YesodPersist App where
    type YesodPersistBackend App = SqlBackend
    runDB :: SqlPersistT Handler a -> Handler a
    runDB action = do
        master <- getYesod
        runSqlPool action $ appConnPool master

instance YesodPersistRunner App where
    getDBRunner :: Handler (DBRunner App, Handler ())
    getDBRunner = defaultGetDBRunner appConnPool

instance HasHttpManager App where
    getHttpManager :: App -> Manager
    getHttpManager = appHttpManager

unsafeHandler :: App -> Handler a -> IO a
unsafeHandler = Unsafe.fakeHandlerGetLogger appLogger
