{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Seed (popular) where

import ClassyPrelude.Yesod
import Data.Time (addDays)
import Database.Persist.Sql (fromSqlKey)
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
    , extraEditora :: Maybe (Text, Maybe Text)
    , extraCapa :: Maybe Text
    , extraExemplares :: Int
    }

acrescentarAcervo :: MonadIO m => ReaderT SqlBackend m ()
acrescentarAcervo = forM_ acervo $ \l -> do
    existente <- selectFirst [LivroTitulo ==. extraTitulo l] []
    case existente of
        Just (Entity livro atual) ->
            when (isNothing (livroCapaUrl atual) && isJust (extraCapa l)) $
                update livro [LivroCapaUrl =. extraCapa l]
        Nothing -> do
            categoria <- either entityKey id <$> insertBy (Categoria (extraCategoria l) Nothing)
            editora <- forM (extraEditora l) $ \(nome, cidade) ->
                either entityKey id <$> insertBy (Editora nome cidade)
            livro <- insert $ Livro (extraTitulo l) Nothing (extraAno l) Nothing (extraCapa l) editora categoria
            autores <- mapM autorPorNome (extraAutores l)
            insertMany_ (LivroAutor livro <$> ordNub autores)
            forM_ [1 .. extraExemplares l] $ \e ->
                void $ insertBy (Exemplar livro ("LV-" <> tshow (fromSqlKey livro) <> "-" <> tshow e) Bom True)

autorPorNome :: MonadIO m => (Text, Maybe Text) -> ReaderT SqlBackend m AutorId
autorPorNome (nome, nacionalidade) =
    selectFirst [AutorNome ==. nome] [] >>= maybe (insert (Autor nome nacionalidade)) (return . entityKey)

acervo :: [LivroExtra]
acervo =
    [ romance 55752 "Dom Casmurro" [machado] (Just 1899) 1
    , romance 54829 "Memórias Póstumas de Brás Cubas" [machado] (Just 1881) 1
    , romance 55682 "Quincas Borba" [machado] (Just 1891) 2
    , romance 56737 "Esaú e Jacó" [machado] (Just 1904) 1
    , romance 55797 "Memorial de Aires" [machado] (Just 1908) 1
    , romance 67162 "Helena" [machado] (Just 1876) 1
    , romance 53101 "A Mão e a Luva" [machado] (Just 1874) 1
    , romance 67780 "Iaiá Garcia" [machado] (Just 1878) 1
    , contos 33056 "Histórias sem Data" [machado] (Just 1884) 1
    , contos 57001 "Papéis Avulsos" [machado] (Just 1882) 2
    , contos 67935 "Relíquias de Casa Velha" [machado] (Just 1906) 1
    , poesia 61653 "Poesias Completas" [machado] (Just 1901) 1
    , romance 67740 "Iracema" [alencar] (Just 1865) 2
    , romance 67724 "O Guarani" [alencar] (Just 1857) 2
    , romance 38496 "Ubirajara" [alencar] (Just 1874) 1
    , romance 44540 "Cinco Minutos" [alencar] (Just 1856) 1
    , romance 69187 "O Cortiço" [("Aluísio Azevedo", brasileira)] (Just 1890) 3
    , romance 68541 "O Ateneu" [("Raul Pompeia", brasileira)] (Just 1888) 1
    , romance 67535 "Triste Fim de Policarpo Quaresma" [("Lima Barreto", brasileira)] (Just 1915) 2
    , poesia 74854 "Cantos" [("Gonçalves Dias", brasileira)] (Just 1857) 1
    , contos 2837 "Lendas do Sul" [("Simões Lopes Neto", brasileira)] (Just 1913) 1
    , romance 40409 "Os Maias" [eca] (Just 1888) 2
    , romance 42942 "O Primo Basílio" [eca] (Just 1878) 2
    , romance 31971 "O Crime do Padre Amaro" [eca] (Just 1875) 1
    , romance 18220 "A Cidade e as Serras" [eca] (Just 1901) 1
    , romance 23145 "A Ilustre Casa de Ramires" [eca] (Just 1900) 1
    , romance 16384 "O Mandarim" [eca] (Just 1880) 1
    , romance 17515 "A Relíquia" [eca] (Just 1887) 1
    , contos 31347 "Contos" [eca] (Just 1902) 1
    , romance 16425 "Amor de Perdição" [camilo] (Just 1862) 2
    , romance 17927 "A Queda dum Anjo" [camilo] (Just 1866) 1
    , romance 26988 "Amor de Salvação" [camilo] (Just 1864) 1
    , contos 21406 "Novelas do Minho" [camilo] Nothing 1
    , romance 29120 "A Morgadinha dos Canaviais" [("Júlio Dinis", portuguesa)] (Just 1868) 1
    , romance 24401 "Viagens na Minha Terra" [("Almeida Garrett", portuguesa)] (Just 1846) 1
    , contos 9654 "Lendas e Narrativas" [("Alexandre Herculano", portuguesa)] (Just 1851) 1
    , poesia 3333 "Os Lusíadas" [("Luís de Camões", portuguesa)] (Just 1572) 2
    , poesia 17610 "Livro de Mágoas" [("Florbela Espanca", portuguesa)] (Just 1919) 1
    , poesia 8698 "O Livro de Cesário Verde" [("Cesário Verde", portuguesa)] (Just 1887) 1
    , poesia 20142 "Sonetos Completos" [("Antero de Quental", portuguesa)] (Just 1886) 1
    , LivroExtra "Da Terra à Lua" [("Júlio Verne", Just "Francesa")] (Just 1865) "Ficção científica" gutenbergEditora (gutenberg 28341) 1
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
    romance = dominioPublico "Romance"
    contos = dominioPublico "Contos"
    poesia = dominioPublico "Poesia"
    dominioPublico categoria pg t autores ano =
        LivroExtra t autores ano categoria gutenbergEditora (gutenberg pg)
    ficcao t autores ano = LivroExtra t autores (Just ano) "Ficção científica" (Just ("Aleph", Just "São Paulo")) Nothing
    tecnico t autores ano = LivroExtra t autores ano "Técnico" Nothing Nothing
    gutenbergEditora = Just ("Project Gutenberg", Nothing)
    gutenberg :: Int -> Maybe Text
    gutenberg pg = Just ("https://www.gutenberg.org/cache/epub/" <> tshow pg <> "/pg" <> tshow pg <> ".cover.medium.jpg")
    brasileira = Just "Brasileira"
    portuguesa = Just "Portuguesa"
    britanica = Just "Britânica"
    estadunidense = Just "Estadunidense"
    machado = ("Machado de Assis", brasileira)
    alencar = ("José de Alencar", brasileira)
    eca = ("Eça de Queirós", portuguesa)
    camilo = ("Camilo Castelo Branco", portuguesa)
    asimov = ("Isaac Asimov", Just "Estadunidense")
