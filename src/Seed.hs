{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Seed (popular) where

import ClassyPrelude.Yesod
import Data.Time (addDays)
import Model
import Model.Tipos
import Regras.Emprestimo (hoje)

popular :: MonadIO m => ReaderT SqlBackend m ()
popular = do
    exemplo
    acrescentarAcervo

exemplo :: MonadIO m => ReaderT SqlBackend m ()
exemplo = do
    categorias <- count ([] :: [Filter Categoria])
    when (categorias == 0) $ do
        dia <- hoje

        romance <- insert $ Categoria "Romance" (Just "Ficção em prosa")
        ficcao <- insert $ Categoria "Ficção científica" Nothing
        _ <- insert $ Categoria "Técnico" (Just "Programação e computação")

        companhia <- insert $ Editora "Companhia das Letras" (Just "São Paulo")
        aleph <- insert $ Editora "Aleph" (Just "São Paulo")

        machado <- insert $ Autor "Machado de Assis" (Just "Brasileira")
        asimov <- insert $ Autor "Isaac Asimov" (Just "Estadunidense")

        domCasmurro <- insert $ Livro "Dom Casmurro" Nothing (Just 1899) Nothing Nothing (Just companhia) romance
        bras <- insert $ Livro "Memórias Póstumas de Brás Cubas" Nothing (Just 1881) Nothing Nothing (Just companhia) romance
        euRobo <- insert $ Livro "Eu, Robô" Nothing (Just 1950) Nothing Nothing (Just aleph) ficcao
        fundacao <- insert $ Livro "Fundação" Nothing (Just 1951) Nothing Nothing (Just aleph) ficcao

        insertMany_
            [ LivroAutor domCasmurro machado
            , LivroAutor bras machado
            , LivroAutor euRobo asimov
            , LivroAutor fundacao asimov
            ]

        dc1 <- insert $ Exemplar domCasmurro "DC-001" Bom False
        _ <- insert $ Exemplar domCasmurro "DC-002" Danificado True
        br1 <- insert $ Exemplar bras "BC-001" Bom True
        _ <- insert $ Exemplar euRobo "ER-001" Bom True
        fu1 <- insert $ Exemplar fundacao "FU-001" Bom False

        ana <- insert $ Socio "Ana Souza" "ana@example.com" (Just "11999990000")
            (Just "01001000") (Just "Praça da Sé") (Just "100") (Just "Sé") (Just "São Paulo") (Just "SP")
        bruno <- insert $ Socio "Bruno Lima" "bruno@example.com" Nothing
            Nothing Nothing Nothing Nothing Nothing Nothing

        insertMany_
            [ Emprestimo dc1 ana (addDays (-20) dia) (addDays (-6) dia) Nothing 0 0 Nothing
            , Emprestimo br1 bruno (addDays (-30) dia) (addDays (-16) dia) (Just (addDays (-14) dia)) 0 0 Nothing
            , Emprestimo fu1 bruno (addDays (-3) dia) (addDays 11 dia) Nothing 0 0 Nothing
            ]

        insert_ $ Reserva fundacao ana dia Ativa

data LivroExtra = LivroExtra
    { extraTitulo :: Text
    , extraAutores :: [(Text, Maybe Text)]
    , extraAno :: Maybe Int
    , extraCategoria :: Text
    , extraEditora :: Maybe Text
    , extraExemplares :: Int
    }

acrescentarAcervo :: MonadIO m => ReaderT SqlBackend m ()
acrescentarAcervo = forM_ (zip [1 :: Int ..] acervo) $ \(n, l) -> do
    existente <- selectFirst [LivroTitulo ==. extraTitulo l] []
    when (isNothing existente) $ do
        categoria <- either entityKey id <$> insertBy (Categoria (extraCategoria l) Nothing)
        editora <- forM (extraEditora l) $ \nome ->
            either entityKey id <$> insertBy (Editora nome (Just "São Paulo"))
        livro <- insert $ Livro (extraTitulo l) Nothing (extraAno l) Nothing Nothing editora categoria
        autores <- mapM autorPorNome (extraAutores l)
        insertMany_ (LivroAutor livro <$> ordNub autores)
        forM_ [1 .. extraExemplares l] $ \e ->
            void $ insertBy (Exemplar livro (codigo n e) Bom True)
  where
    codigo n e = "AC-" <> (if n < 10 then "0" else "") <> tshow n <> "-" <> tshow e

autorPorNome :: MonadIO m => (Text, Maybe Text) -> ReaderT SqlBackend m AutorId
autorPorNome (nome, nacionalidade) =
    selectFirst [AutorNome ==. nome] [] >>= maybe (insert (Autor nome nacionalidade)) (return . entityKey)

acervo :: [LivroExtra]
acervo =
    [ romance "Quincas Borba" [machado] 1891 2
    , romance "Esaú e Jacó" [machado] 1904 1
    , romance "Memorial de Aires" [machado] 1908 1
    , romance "Helena" [machado] 1876 1
    , romance "Iracema" [alencar] 1865 2
    , romance "O Guarani" [alencar] 1857 1
    , romance "Senhora" [alencar] 1875 2
    , romance "O Cortiço" [("Aluísio Azevedo", brasileira)] 1890 3
    , romance "O Ateneu" [("Raul Pompeia", brasileira)] 1888 1
    , romance "Triste Fim de Policarpo Quaresma" [("Lima Barreto", brasileira)] 1915 2
    , romance "Vidas Secas" [graciliano] 1938 3
    , romance "São Bernardo" [graciliano] 1934 1
    , romance "Capitães da Areia" [("Jorge Amado", brasileira)] 1937 2
    , romance "A Hora da Estrela" [("Clarice Lispector", brasileira)] 1977 2
    , romance "Grande Sertão: Veredas" [("João Guimarães Rosa", brasileira)] 1956 1
    , romance "Macunaíma" [("Mário de Andrade", brasileira)] 1928 1
    , romance "Os Maias" [("Eça de Queirós", Just "Portuguesa")] 1888 1
    , romance "Orgulho e Preconceito" [("Jane Austen", britanica)] 1813 2
    , ficcao "1984" [("George Orwell", britanica)] 1949 3
    , ficcao "Admirável Mundo Novo" [("Aldous Huxley", britanica)] 1932 2
    , ficcao "Fundação e Império" [asimov] 1952 1
    , ficcao "Segunda Fundação" [asimov] 1953 1
    , ficcao "O Fim da Eternidade" [asimov] 1955 1
    , ficcao "Os Próprios Deuses" [asimov] 1972 1
    , ficcao "Androides Sonham com Ovelhas Elétricas?" [("Philip K. Dick", estadunidense)] 1968 1
    , ficcao "2001: Uma Odisseia no Espaço" [("Arthur C. Clarke", britanica)] 1968 2
    , ficcao "Neuromancer" [("William Gibson", estadunidense)] 1984 1
    , ficcao "A Mão Esquerda da Escuridão" [("Ursula K. Le Guin", estadunidense)] 1969 1
    , ficcao "Duna" [("Frank Herbert", estadunidense)] 1965 3
    , ficcao "Fahrenheit 451" [("Ray Bradbury", estadunidense)] 1953 2
    , ficcao "Frankenstein" [("Mary Shelley", britanica)] 1818 1
    , ficcao "A Máquina do Tempo" [("H. G. Wells", britanica)] 1895 1
    , tecnico "Estrutura e Interpretação de Programas de Computador"
        [("Harold Abelson", estadunidense), ("Gerald Jay Sussman", estadunidense)] (Just 1985) 1
    , tecnico "Programming in Haskell" [("Graham Hutton", britanica)] (Just 2007) 1
    , tecnico "Learn You a Haskell for Great Good!" [("Miran Lipovača", Nothing)] (Just 2011) 1
    , tecnico "Haskell: Uma Introdução à Programação Funcional"
        [("Alexandre Garcia de Oliveira", brasileira)] Nothing 2
    , tecnico "Código Limpo" [("Robert C. Martin", estadunidense)] (Just 2008) 2
    , tecnico "O Programador Pragmático" [("Andrew Hunt", Nothing), ("David Thomas", Nothing)] (Just 1999) 1
    , tecnico "Padrões de Projeto"
        [("Erich Gamma", Nothing), ("Richard Helm", Nothing), ("Ralph Johnson", Nothing), ("John Vlissides", Nothing)]
        (Just 1994) 1
    , tecnico "Entendendo Algoritmos" [("Aditya Bhargava", Nothing)] (Just 2016) 2
    , tecnico "Algoritmos: Teoria e Prática"
        [("Thomas H. Cormen", estadunidense), ("Charles E. Leiserson", estadunidense), ("Ronald L. Rivest", estadunidense), ("Clifford Stein", estadunidense)]
        (Just 1990) 1
    ]
  where
    romance t autores ano = LivroExtra t autores (Just ano) "Romance" (Just "Companhia das Letras")
    ficcao t autores ano = LivroExtra t autores (Just ano) "Ficção científica" (Just "Aleph")
    tecnico t autores ano = LivroExtra t autores ano "Técnico" Nothing
    brasileira = Just "Brasileira"
    britanica = Just "Britânica"
    estadunidense = Just "Estadunidense"
    machado = ("Machado de Assis", brasileira)
    alencar = ("José de Alencar", brasileira)
    graciliano = ("Graciliano Ramos", brasileira)
    asimov = ("Isaac Asimov", Just "Estadunidense")
