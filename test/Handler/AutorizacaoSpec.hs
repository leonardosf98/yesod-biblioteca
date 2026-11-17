{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Handler.AutorizacaoSpec (spec) where

import TestImport
import Usuario (salvarBibliotecario)

entrarComSenha :: Text -> Text -> YesodExample App ()
entrarComSenha login senha = do
    get (AuthR LoginR)
    request $ do
        setMethod "POST"
        setUrl (AuthR (PluginR "hashdb" ["login"]))
        addToken_ "#form-login"
        addPostParam "username" login
        addPostParam "password" senha

vaiParaLogin :: YesodExample App ()
vaiParaLogin = do
    statusIs 303
    destino <- getLocation
    assertEq "redireciona ao login" (Right (AuthR LoginR)) destino

spec :: Spec
spec = withApp $ describe "Autorização" $ do
    it "visitante vê o catálogo" $ do
        get LivrosR
        statusIs 200
        get AutoresR
        statusIs 200

    it "visitante é mandado ao login nas áreas restritas e nos formulários" $ do
        get SociosR
        vaiParaLogin
        get EmprestimosR
        vaiParaLogin
        get AutorNovoR
        vaiParaLogin

    it "visitante não vê os itens restritos do menu" $ do
        get HomeR
        htmlNoneContain ".navbar a" "Sócios"
        htmlAnyContain ".navbar a" "Entrar"

    it "bibliotecário vê os itens restritos do menu" $ do
        entrar
        get HomeR
        htmlAnyContain ".navbar a" "Sócios"
        htmlAnyContain ".navbar a" "Sair"

    it "usuário com papel de sócio não acessa a área do bibliotecário" $ do
        criarUsuario PapelSocio "socio@example.com" >>= authenticateAs
        get SociosR
        statusIs 403

    it "bibliotecário entra com a senha cadastrada" $ do
        _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        entrarComSenha "maria" "senha-forte-123"
        get SociosR
        statusIs 200

    it "senha errada não entra" $ do
        _ <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        entrarComSenha "maria" "senha-errada"
        get SociosR
        vaiParaLogin

    it "senha é guardada com hash" $ do
        usuarioId <- runDB $ salvarBibliotecario "maria" "senha-forte-123"
        usuario <- runDB $ getJust usuarioId
        assertEq "não é texto puro" False (userPassword usuario == Just "senha-forte-123")
        assertEq "tem hash" True (isJust (userPassword usuario))

    it "login de identificador desconhecido não cria usuário" $ do
        get (AuthR LoginR)
        request $ do
            setMethod "POST"
            setUrl (AuthR (PluginR "dummy" []))
            addToken_ "#form-login"
            addPostParam "ident" "invasor"
        usuarios <- runDB $ count ([] :: [Filter User])
        assertEq "nenhum usuário criado" 0 usuarios
        get SociosR
        vaiParaLogin
