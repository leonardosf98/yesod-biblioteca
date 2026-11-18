import Application (db)
import Rotina (rodarRotina)

main :: IO ()
main = do
    novas <- db rodarRotina
    putStrLn ("Rotina concluída: " <> show novas <> " notificação(ões) nova(s).")
