import Application (db)
import qualified Data.Text as T
import System.Environment (getArgs)
import System.Exit (die)
import Control.Exception (bracket_)
import System.IO (hFlush, hIsTerminalDevice, hPutStr, hSetEcho, stderr, stdin)
import Usuario (salvarBibliotecario)

main :: IO ()
main = do
    argumentos <- getArgs
    login <- case argumentos of
        [login] -> return (T.pack login)
        _ -> die "Uso: stack exec biblioteca-usuario -- <login>"
    hPutStr stderr "Senha: "
    hFlush stderr
    senha <- T.pack <$> lerSenha
    if T.length senha < 8
        then die "A senha precisa ter pelo menos 8 caracteres."
        else do
            _ <- db (salvarBibliotecario login senha)
            putStrLn ("Bibliotecário " <> T.unpack login <> " salvo.")

lerSenha :: IO String
lerSenha = do
    terminal <- hIsTerminalDevice stdin
    if terminal
        then bracket_ (hSetEcho stdin False) (hSetEcho stdin True >> hPutStr stderr "\n") getLine
        else getLine
