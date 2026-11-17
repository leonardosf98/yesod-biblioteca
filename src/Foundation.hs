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
import Data.Kind            (Type)
import Database.Persist.Sql (ConnectionPool, runSqlPool)
import Text.Hamlet          (hamletFile)
import Text.Jasmine         (minifym)
import Control.Monad.Logger (LogSource)

-- Used only when in "auth-dummy-login" setting is enabled.
import Yesod.Auth.Dummy
import Yesod.Form.I18n.Portuguese (portugueseFormMessage)

import Yesod.Auth.HashDB    (authHashDBWithForm)
import Yesod.Auth.Message   (AuthMessage (InvalidLogin), portugueseMessage)
import Yesod.Default.Util   (addStaticContentExternal)
import Yesod.Core.Types     (Logger)
import qualified Yesod.Core.Unsafe as Unsafe
import qualified Data.CaseInsensitive as CI
import qualified Data.Text.Encoding as TE
import Sessao (hashToken)
import Network.Wai (pathInfo)

-- | The foundation datatype for your application. This can be a good place to
-- keep settings and values requiring initialization before your application
-- starts running, such as database connections. Every handler will have
-- access to the data present here.
data App = App
    { appSettings    :: AppSettings
    , appStatic      :: Static -- ^ Settings for static file serving.
    , appConnPool    :: ConnectionPool -- ^ Database connection pool.
    , appHttpManager :: Manager
    , appLogger      :: Logger
    }

data MenuItem = MenuItem
    { menuItemLabel :: Text
    , menuItemRoute :: Route App
    , menuItemAccessCallback :: Bool
    }

data MenuTypes
    = NavbarLeft MenuItem
    | NavbarRight MenuItem

-- This is where we define all of the routes in our application. For a full
-- explanation of the syntax, please see:
-- http://www.yesodweb.com/book/routing-and-handlers
--
-- Note that this is really half the story; in Application.hs, mkYesodDispatch
-- generates the rest of the code. Please see the following documentation
-- for an explanation for this split:
-- http://www.yesodweb.com/book/scaffolding-and-the-site-template#scaffolding-and-the-site-template_foundation_and_application_modules
--
-- This function also generates the following type synonyms:
-- type Handler = HandlerFor App
-- type Widget = WidgetFor App ()
mkYesodData "App" $(parseRoutesFile "config/routes.yesodroutes")

-- | A convenient synonym for creating forms.
type Form x = Html -> MForm (HandlerFor App) (FormResult x, Widget)

-- | A convenient synonym for database access functions.
type DB a = forall (m :: Type -> Type).
    (MonadUnliftIO m) => ReaderT SqlBackend m a

-- Please see the documentation for the Yesod typeclass. There are a number
-- of settings which can be configured by overriding methods here.
instance Yesod App where
    -- Controls the base of generated URLs. For more information on modifying,
    -- see: https://github.com/yesodweb/yesod/wiki/Overriding-approot
    approot :: Approot App
    approot = ApprootRequest $ \app req ->
        case appRoot $ appSettings app of
            Nothing -> getApprootText guessApproot app req
            Just root -> root

    -- Store session data on the client in encrypted cookies,
    -- default session idle timeout is 120 minutes
    makeSessionBackend :: App -> IO (Maybe SessionBackend)
    makeSessionBackend _ = Just <$> defaultClientSessionBackend
        120    -- timeout in minutes
        "config/client_session_key.aes"

    -- Yesod Middleware allows you to run code before and after each handler function.
    -- The defaultYesodMiddleware adds the response header "Vary: Accept, Accept-Language" and performs authorization checks.
    -- Some users may also want to add the defaultCsrfMiddleware, which:
    --   a) Sets a cookie with a CSRF token in it.
    --   b) Validates that incoming write requests include that token in either a header or POST parameter.
    -- To add it, chain it together with the defaultMiddleware: yesodMiddleware = defaultYesodMiddleware . defaultCsrfMiddleware
    -- For details, see the CSRF documentation in the Yesod.Core.Handler module of the yesod-core package.
    yesodMiddleware :: ToTypedContent res => Handler res -> Handler res
    yesodMiddleware = defaultYesodMiddleware . csrfForaDaApi

    defaultLayout :: Widget -> Handler Html
    defaultLayout widget = do
        master <- getYesod
        mensagens <- getMessages

        mcurrentRoute <- getCurrentRoute
        usuario <- maybeAuth
        let bibliotecario = maybe False ((== PapelBibliotecario) . userPapel . entityVal) usuario

        -- Get the breadcrumbs, as defined in the YesodBreadcrumbs instance.
        (title, parents) <- breadcrumbs

        -- Define the menu items of the header.
        let menuItems =
                [ NavbarLeft $ MenuItem
                    { menuItemLabel = "Início"
                    , menuItemRoute = HomeR
                    , menuItemAccessCallback = True
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Livros"
                    , menuItemRoute = LivrosR
                    , menuItemAccessCallback = True
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Autores"
                    , menuItemRoute = AutoresR
                    , menuItemAccessCallback = True
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Editoras"
                    , menuItemRoute = EditorasR
                    , menuItemAccessCallback = True
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Categorias"
                    , menuItemRoute = CategoriasR
                    , menuItemAccessCallback = True
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Sócios"
                    , menuItemRoute = SociosR
                    , menuItemAccessCallback = bibliotecario
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Empréstimos"
                    , menuItemRoute = EmprestimosR
                    , menuItemAccessCallback = bibliotecario
                    }
                , NavbarLeft $ MenuItem
                    { menuItemLabel = "Reservas"
                    , menuItemRoute = ReservasR
                    , menuItemAccessCallback = bibliotecario
                    }
                , NavbarRight $ MenuItem
                    { menuItemLabel = "Entrar"
                    , menuItemRoute = AuthR LoginR
                    , menuItemAccessCallback = isNothing usuario
                    }
                , NavbarRight $ MenuItem
                    { menuItemLabel = "Sair"
                    , menuItemRoute = AuthR LogoutR
                    , menuItemAccessCallback = isJust usuario
                    }
                ]

        let navbarLeftMenuItems = [x | NavbarLeft x <- menuItems]
        let navbarRightMenuItems = [x | NavbarRight x <- menuItems]

        let navbarLeftFilteredMenuItems = [x | x <- navbarLeftMenuItems, menuItemAccessCallback x]
        let navbarRightFilteredMenuItems = [x | x <- navbarRightMenuItems, menuItemAccessCallback x]

        -- We break up the default layout into two components:
        -- default-layout is the contents of the body tag, and
        -- default-layout-wrapper is the entire page. Since the final
        -- value passed to hamletToRepHtml cannot be a widget, this allows
        -- you to use normal widget features in default-layout.

        pc <- widgetToPageContent $ do
            addStylesheet $ StaticR css_bootstrap_css
                                    -- ^ generated from @Settings/StaticFiles.hs@
            $(widgetFile "default-layout")
        withUrlRenderer $(hamletFile "templates/default-layout-wrapper.hamlet")

    -- The page to be redirected to when authentication is required.
    authRoute
        :: App
        -> Maybe (Route App)
    authRoute _ = Just $ AuthR LoginR

    isAuthorized
        :: Route App  -- ^ The route the user is visiting.
        -> Bool       -- ^ Whether or not this is a "write" request.
        -> Handler AuthResult
    -- Routes not requiring authentication.
    isAuthorized rota escrita
        | rotaLivre rota = return Authorized
        | not escrita && catalogo rota = return Authorized
        | rota == ApiEuR = exigirLogin
        | otherwise = exigirPapel PapelBibliotecario

    -- This function creates static content files in the static folder
    -- and names them based on a hash of their content. This allows
    -- expiration dates to be set far in the future without worry of
    -- users receiving stale content.
    addStaticContent
        :: Text  -- ^ The file extension
        -> Text -- ^ The MIME content type
        -> LByteString -- ^ The contents of the file
        -> Handler (Maybe (Either Text (Route App, [(Text, Text)])))
    addStaticContent ext mime content = do
        master <- getYesod
        let staticDir = appStaticDir $ appSettings master
        addStaticContentExternal
            minifym
            genFileName
            staticDir
            (StaticR . flip StaticRoute [])
            ext
            mime
            content
      where
        -- Generate a unique filename based on the content itself
        genFileName lbs = "autogen-" ++ base64md5 lbs

    -- What messages should be logged. The following includes all messages when
    -- in development, and warnings and errors in production.
    shouldLogIO :: App -> LogSource -> LogLevel -> IO Bool
    shouldLogIO app _source level =
        return $
        appShouldLogAll (appSettings app)
            || level == LevelWarn
            || level == LevelError

    makeLogger :: App -> IO Logger
    makeLogger = return . appLogger

    errorHandler :: ErrorResponse -> Handler TypedContent
    errorHandler NotFound = paginaDeErro "Página não encontrada" "O endereço não existe ou o registro foi excluído."
    errorHandler (InternalError _) = paginaDeErro "Algo deu errado" "Ocorreu um erro inesperado. Tente de novo; se continuar, avise a equipe."
    errorHandler (PermissionDenied _) = paginaDeErro "Acesso negado" "A requisição foi recusada. Recarregue a página e tente de novo."
    errorHandler outro = defaultErrorHandler outro

paginaDeErro :: Text -> Text -> Handler TypedContent
paginaDeErro titulo explicacao = selectRep $ do
  provideRep $ defaultLayout $ do
    setTitle (toHtml titulo)
    [whamlet|
<div .pagina-erro>
    <h1>#{titulo}
    <p .lead>#{explicacao}
    <a .btn .btn-primary href=@{HomeR}>Voltar ao início
|]
  provideRep $ return $ object ["erro" .= explicacao]

rotaDaApi :: [Text] -> Bool
rotaDaApi ("api" : _) = True
rotaDaApi _ = False

-- A API autentica só pelo cabeçalho Bearer, nunca pelo cookie de sessão; por isso dispensa o token CSRF.
csrfForaDaApi :: Handler res -> Handler res
csrfForaDaApi handler = do
    caminho <- pathInfo <$> waiRequest
    if rotaDaApi caminho then handler else defaultCsrfMiddleware handler

usuarioDoToken :: Handler (Maybe UserId)
usuarioDoToken = do
    token <- lookupBearerAuth
    case token of
        Nothing -> return Nothing
        Just valor -> do
            agora <- liftIO getCurrentTime
            sessao <- runDB $ getBy (UniqueSessaoToken (hashToken valor))
            return $ case sessao of
                Just (Entity _ s) | sessaoExpiraEm s > agora -> Just (sessaoUserId s)
                _ -> Nothing

rotaLivre :: Route App -> Bool
rotaLivre rota = case rota of
    AuthR _ -> True
    HomeR -> True
    FaviconR -> True
    RobotsR -> True
    StaticR _ -> True
    ApiSessoesR -> True
    _ -> False

catalogo :: Route App -> Bool
catalogo rota = case rota of
    LivrosR -> True
    LivroR _ -> True
    AutoresR -> True
    AutorR _ -> True
    EditorasR -> True
    EditoraR _ -> True
    CategoriasR -> True
    CategoriaR _ -> True
    _ -> False

exigirPapel :: Papel -> Handler AuthResult
exigirPapel papel = do
    usuario <- maybeAuth
    return $ case usuario of
        Nothing -> AuthenticationRequired
        Just (Entity _ u)
            | userPapel u == papel -> Authorized
            | otherwise -> Unauthorized "Acesso restrito ao bibliotecário."

exigirLogin :: Handler AuthResult
exigirLogin = maybe AuthenticationRequired (const Authorized) <$> maybeAuthId

formularioLogin :: Route App -> Widget
formularioLogin acao = do
    token <- reqToken <$> getRequest
    [whamlet|
<div .pagina-login>
    <h1>Entrar
    <form #form-login method=post action=@{acao}>
        $maybe valor <- token
            <input type=hidden name=#{defaultCsrfParamName} value=#{valor}>
        <div .form-group>
            <label for=login-usuario>Usuário
            <input .form-control #login-usuario name=username autofocus required>
        <div .form-group>
            <label for=login-senha>Senha
            <input .form-control #login-senha type=password name=password required>
        <button .btn .btn-primary type=submit>Entrar
|]

-- Define breadcrumbs.
instance YesodBreadcrumbs App where
    -- Takes the route that the user is currently on, and returns a tuple
    -- of the 'Text' that you want the label to display, and a previous
    -- breadcrumb route.
    breadcrumb
        :: Route App  -- ^ The route the user is visiting currently.
        -> Handler (Text, Maybe (Route App))
    breadcrumb HomeR = return ("Início", Nothing)
    breadcrumb (AuthR _) = return ("Entrar", Just HomeR)
    breadcrumb AutoresR = return ("Autores", Just HomeR)
    breadcrumb AutorNovoR = return ("Novo autor", Just AutoresR)
    breadcrumb (AutorR autorId) = do
        nome <- maybe "Não encontrado" autorNome <$> runDB (get autorId)
        return (nome, Just AutoresR)
    breadcrumb (AutorEditarR autorId) = return ("Editar", Just (AutorR autorId))
    breadcrumb EditorasR = return ("Editoras", Just HomeR)
    breadcrumb EditoraNovaR = return ("Nova editora", Just EditorasR)
    breadcrumb (EditoraR editoraId) = do
        nome <- maybe "Não encontrado" editoraNome <$> runDB (get editoraId)
        return (nome, Just EditorasR)
    breadcrumb (EditoraEditarR editoraId) = return ("Editar", Just (EditoraR editoraId))
    breadcrumb CategoriasR = return ("Categorias", Just HomeR)
    breadcrumb CategoriaNovaR = return ("Nova categoria", Just CategoriasR)
    breadcrumb (CategoriaR categoriaId) = do
        nome <- maybe "Não encontrado" categoriaNome <$> runDB (get categoriaId)
        return (nome, Just CategoriasR)
    breadcrumb (CategoriaEditarR categoriaId) = return ("Editar", Just (CategoriaR categoriaId))
    breadcrumb LivrosR = return ("Livros", Just HomeR)
    breadcrumb LivroNovoR = return ("Novo livro", Just LivrosR)
    breadcrumb LivroImportarR = return ("Importar por ISBN", Just LivrosR)
    breadcrumb (LivroR livroId) = do
        nome <- maybe "Não encontrado" livroTitulo <$> runDB (get livroId)
        return (nome, Just LivrosR)
    breadcrumb (LivroEditarR livroId) = return ("Editar", Just (LivroR livroId))
    breadcrumb (ExemplarNovoR livroId) = return ("Novo exemplar", Just (LivroR livroId))
    breadcrumb (ExemplarEditarR exemplarId) = do
        exemplar <- runDB $ get exemplarId
        return (maybe "Não encontrado" (("Exemplar " <>) . exemplarCodigo) exemplar, LivroR . exemplarLivroId <$> exemplar)
    breadcrumb SociosR = return ("Sócios", Just HomeR)
    breadcrumb SocioNovoR = return ("Novo sócio", Just SociosR)
    breadcrumb (SocioR socioId) = do
        nome <- maybe "Não encontrado" socioNome <$> runDB (get socioId)
        return (nome, Just SociosR)
    breadcrumb (SocioEditarR socioId) = return ("Editar", Just (SocioR socioId))
    breadcrumb EmprestimosR = return ("Empréstimos", Just HomeR)
    breadcrumb EmprestimoNovoR = return ("Novo empréstimo", Just EmprestimosR)
    breadcrumb (EmprestimoR emprestimoId) = return ("Empréstimo #" <> toPathPiece emprestimoId, Just EmprestimosR)
    breadcrumb (EmprestimoEditarR emprestimoId) = return ("Prorrogar", Just (EmprestimoR emprestimoId))
    breadcrumb ReservasR = return ("Reservas", Just HomeR)
    breadcrumb ReservaNovaR = return ("Nova reserva", Just ReservasR)
    breadcrumb  _ = return ("Início", Nothing)

-- How to run database actions.
instance YesodPersist App where
    type YesodPersistBackend App = SqlBackend
    runDB :: SqlPersistT Handler a -> Handler a
    runDB action = do
        master <- getYesod
        runSqlPool action $ appConnPool master

instance YesodPersistRunner App where
    getDBRunner :: Handler (DBRunner App, Handler ())
    getDBRunner = defaultGetDBRunner appConnPool

instance YesodAuth App where
    type AuthId App = UserId

    -- Where to send a user after successful login
    loginDest :: App -> Route App
    loginDest _ = HomeR
    -- Where to send a user after logout
    logoutDest :: App -> Route App
    logoutDest _ = HomeR
    -- Override the above two destinations when a Referer: header is present
    redirectToReferer :: App -> Bool
    redirectToReferer _ = True

    authenticate creds = liftHandler $ runDB $ do
        x <- getBy $ UniqueUser $ credsIdent creds
        return $ case x of
            Just (Entity uid _) -> Authenticated uid
            Nothing -> UserError InvalidLogin

    -- You can add other plugins like Google Email, email or OAuth here
    authPlugins :: App -> [AuthPlugin App]
    authPlugins app = authHashDBWithForm formularioLogin (Just . UniqueUser) : extraAuthPlugins
        -- Enable authDummy login if enabled.
        where extraAuthPlugins = [authDummy | appAuthDummyLogin $ appSettings app]

    maybeAuthId = liftHandler $ do
        caminho <- pathInfo <$> waiRequest
        if rotaDaApi caminho then usuarioDoToken else defaultMaybeAuthId

    renderAuthMessage :: App -> [Text] -> AuthMessage -> Text
    renderAuthMessage _ _ = portugueseMessage

instance YesodAuthPersist App

-- This instance is required to use forms. You can modify renderMessage to
-- achieve customized and internationalized form validation messages.
instance RenderMessage App FormMessage where
    renderMessage :: App -> [Lang] -> FormMessage -> Text
    renderMessage _ _ = portugueseFormMessage

-- Useful when writing code that is re-usable outside of the Handler context.
-- An example is background jobs that send email.
-- This can also be useful for writing code that works across multiple Yesod applications.
instance HasHttpManager App where
    getHttpManager :: App -> Manager
    getHttpManager = appHttpManager

unsafeHandler :: App -> Handler a -> IO a
unsafeHandler = Unsafe.fakeHandlerGetLogger appLogger

-- Note: Some functionality previously present in the scaffolding has been
-- moved to documentation in the Wiki. Following are some hopefully helpful
-- links:
--
-- https://github.com/yesodweb/yesod/wiki/Sending-email
-- https://github.com/yesodweb/yesod/wiki/Serve-static-files-from-a-separate-domain
-- https://github.com/yesodweb/yesod/wiki/i18n-messages-in-the-scaffolding
