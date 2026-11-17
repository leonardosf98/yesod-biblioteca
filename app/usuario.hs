import Application (db)
import qualified Data.Text as T
import System.Environment (getArgs)
import System.Exit (die)
import System.IO (hFlush, hPutStr, hSetEcho, stderr, stdin)
import Usuario (salvarBibliotecario)

main :: IO ()
main = do
    argumentos <- getArgs
    login <- case argumentos of
        [login] -> return (T.pack login)
        _ -> die "Uso: stack exec biblioteca-usuario -- <login>"
    hPutStr stderr "Senha: "
    hFlush stderr
    hSetEcho stdin False
    senha <- T.pack <$> getLine
    hSetEcho stdin True
    hPutStr stderr "\n"
    if T.length senha < 8
        then die "A senha precisa ter pelo menos 8 caracteres."
        else do
            _ <- db (salvarBibliotecario login senha)
            putStrLn ("Bibliotecário " <> T.unpack login <> " salvo.")
