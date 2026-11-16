import Application (db)
import Seed (popular)

main :: IO ()
main = db popular
