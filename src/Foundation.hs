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
import Sessao (hashToken)
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
    isAuthorized rota escrita
        | rotaLivre rota = return Authorized
        | not escrita && catalogo rota = return Authorized
        | rota == ApiEuR || rotaDeNotificacao rota = exigirLogin
        | rotaDoSocio rota = exigirPapel PapelSocio
        | otherwise = exigirPapel PapelBibliotecario

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

rotaLivre :: Route App -> Bool
rotaLivre rota = case rota of
    HomeR -> True
    FaviconR -> True
    RobotsR -> True
    ApiSessoesR -> True
    ApiAtivacaoR -> True
    _ -> False

catalogo :: Route App -> Bool
catalogo rota = case rota of
    ApiLivrosR -> True
    ApiLivroR _ -> True
    ApiAutoresR -> True
    ApiEditorasR -> True
    ApiCategoriasR -> True
    _ -> False

rotaDeNotificacao :: Route App -> Bool
rotaDeNotificacao rota = case rota of
    ApiNotificacoesR -> True
    ApiNotificacoesLeituraR -> True
    ApiNotificacaoLeituraR _ -> True
    _ -> False

rotaDoSocio :: Route App -> Bool
rotaDoSocio rota = case rota of
    ApiLivroPedidosR _ -> True
    ApiEuPedidoR _ -> True
    ApiEuEmprestimosR -> True
    ApiEuRenovacaoR _ -> True
    ApiLivroReservasR _ -> True
    ApiEuReservaR _ -> True
    _ -> False

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

exigirLogin :: Handler AuthResult
exigirLogin = maybe AuthenticationRequired (const Authorized) <$> usuarioAtual

exigirPapel :: Papel -> Handler AuthResult
exigirPapel papel = do
    usuario <- usuarioAtual
    return $ case usuario of
        Nothing -> AuthenticationRequired
        Just (Entity _ u)
            | userPapel u == papel -> Authorized
            | otherwise -> Unauthorized $ case papel of
                PapelBibliotecario -> "Acesso restrito ao bibliotecário."
                PapelSocio -> "Acesso restrito a sócios."

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
