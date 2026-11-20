{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Seed (popular) where

import ClassyPrelude.Yesod
import Data.Time (addDays)
import Database.Persist.Sql (fromSqlKey)
import Model
import Model.Tipos
import Regras.Comum (hoje)

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
    [ romance (Just "dom-casmurro") "Dom Casmurro" [machado] (Just 1899) 1
    , romance (Just "memorias-postumas-de-bras-cubas") "Memórias Póstumas de Brás Cubas" [machado] (Just 1881) 1
    , romance (Just "quincas-borba") "Quincas Borba" [machado] (Just 1891) 2
    , romance (Just "esau-e-jaco") "Esaú e Jacó" [machado] (Just 1904) 1
    , romance (Just "memorial-de-aires") "Memorial de Aires" [machado] (Just 1908) 1
    , romance (Just "helena") "Helena" [machado] (Just 1876) 1
    , romance (Just "a-mao-e-a-luva") "A Mão e a Luva" [machado] (Just 1874) 1
    , romance (Just "iaia-garcia") "Iaiá Garcia" [machado] (Just 1878) 1
    , contos (Just "historias-sem-data") "Histórias sem Data" [machado] (Just 1884) 1
    , contos (Just "papeis-avulsos") "Papéis Avulsos" [machado] (Just 1882) 2
    , contos (Just "reliquias-de-casa-velha") "Relíquias de Casa Velha" [machado] (Just 1906) 1
    , poesia Nothing "Poesias Completas" [machado] (Just 1901) 1
    , romance (Just "iracema") "Iracema" [alencar] (Just 1865) 2
    , romance (Just "o-guarani") "O Guarani" [alencar] (Just 1857) 2
    , romance (Just "ubirajara") "Ubirajara" [alencar] (Just 1874) 1
    , romance (Just "cinco-minutos") "Cinco Minutos" [alencar] (Just 1856) 1
    , romance (Just "a-viuvinha") "A Viuvinha" [alencar] (Just 1860) 1
    , romance (Just "o-cortico") "O Cortiço" [("Aluísio Azevedo", brasileira)] (Just 1890) 3
    , romance (Just "o-ateneu") "O Ateneu" [("Raul Pompeia", brasileira)] (Just 1888) 1
    , romance (Just "triste-fim-de-policarpo-quaresma") "Triste Fim de Policarpo Quaresma" [("Lima Barreto", brasileira)] (Just 1915) 2
    , poesia (Just "cantos") "Cantos" [("Gonçalves Dias", brasileira)] (Just 1857) 1
    , contos Nothing "Lendas do Sul" [("Simões Lopes Neto", brasileira)] (Just 1913) 1
    , romance (Just "os-maias") "Os Maias" [eca] (Just 1888) 2
    , romance (Just "o-primo-basilio") "O Primo Basílio" [eca] (Just 1878) 2
    , romance (Just "o-crime-do-padre-amaro") "O Crime do Padre Amaro" [eca] (Just 1875) 1
    , romance (Just "a-cidade-e-as-serras") "A Cidade e as Serras" [eca] (Just 1901) 1
    , romance (Just "a-ilustre-casa-de-ramires") "A Ilustre Casa de Ramires" [eca] (Just 1900) 1
    , romance (Just "o-mandarim") "O Mandarim" [eca] (Just 1880) 1
    , romance (Just "a-reliquia") "A Relíquia" [eca] (Just 1887) 1
    , contos (Just "contos-eca") "Contos" [eca] (Just 1902) 1
    , romance (Just "amor-de-perdicao") "Amor de Perdição" [camilo] (Just 1862) 2
    , romance (Just "a-queda-dum-anjo") "A Queda dum Anjo" [camilo] (Just 1866) 1
    , romance (Just "amor-de-salvacao") "Amor de Salvação" [camilo] (Just 1864) 1
    , contos (Just "novelas-do-minho") "Novelas do Minho" [camilo] Nothing 1
    , romance (Just "a-morgadinha-dos-canaviais") "A Morgadinha dos Canaviais" [("Júlio Dinis", portuguesa)] (Just 1868) 1
    , romance (Just "viagens-na-minha-terra") "Viagens na Minha Terra" [("Almeida Garrett", portuguesa)] (Just 1846) 1
    , contos (Just "lendas-e-narrativas") "Lendas e Narrativas" [("Alexandre Herculano", portuguesa)] (Just 1851) 1
    , poesia (Just "os-lusiadas") "Os Lusíadas" [("Luís de Camões", portuguesa)] (Just 1572) 2
    , poesia (Just "livro-de-magoas") "Livro de Mágoas" [("Florbela Espanca", portuguesa)] (Just 1919) 1
    , poesia (Just "o-livro-de-cesario-verde") "O Livro de Cesário Verde" [("Cesário Verde", portuguesa)] (Just 1887) 1
    , poesia (Just "sonetos-completos") "Sonetos Completos" [("Antero de Quental", portuguesa)] (Just 1886) 1
    , LivroExtra "Da Terra à Lua" [("Júlio Verne", Just "Francesa")] (Just 1865) "Ficção científica" gutenbergEditora (capa "da-terra-a-lua") 1
    , ficcao (Just "eu-robo") "Eu, Robô" [asimov] 1950 1
    , ficcao (Just "fundacao") "Fundação" [asimov] 1951 1
    , ficcao (Just "1984") "1984" [("George Orwell", britanica)] 1949 3
    , ficcao (Just "admiravel-mundo-novo") "Admirável Mundo Novo" [("Aldous Huxley", britanica)] 1932 2
    , ficcao (Just "fundacao-e-imperio") "Fundação e Império" [asimov] 1952 1
    , ficcao (Just "segunda-fundacao") "Segunda Fundação" [asimov] 1953 1
    , ficcao (Just "o-fim-da-eternidade") "O Fim da Eternidade" [asimov] 1955 1
    , ficcao (Just "os-proprios-deuses") "Os Próprios Deuses" [asimov] 1972 1
    , ficcao (Just "androides-sonham-com-ovelhas-eletricas") "Androides Sonham com Ovelhas Elétricas?" [("Philip K. Dick", estadunidense)] 1968 1
    , ficcao (Just "2001-uma-odisseia-no-espaco") "2001: Uma Odisseia no Espaço" [("Arthur C. Clarke", britanica)] 1968 2
    , ficcao (Just "neuromancer") "Neuromancer" [("William Gibson", estadunidense)] 1984 1
    , ficcao (Just "a-mao-esquerda-da-escuridao") "A Mão Esquerda da Escuridão" [("Ursula K. Le Guin", estadunidense)] 1969 1
    , ficcao (Just "duna") "Duna" [("Frank Herbert", estadunidense)] 1965 3
    , ficcao (Just "fahrenheit-451") "Fahrenheit 451" [("Ray Bradbury", estadunidense)] 1953 2
    , ficcao (Just "frankenstein") "Frankenstein" [("Mary Shelley", britanica)] 1818 1
    , ficcao (Just "a-maquina-do-tempo") "A Máquina do Tempo" [("H. G. Wells", britanica)] 1895 1
    , tecnico (Just "estrutura-e-interpretacao-de-programas-de-computador") "Estrutura e Interpretação de Programas de Computador"
        [("Harold Abelson", estadunidense), ("Gerald Jay Sussman", estadunidense)] (Just 1985) 1
    , tecnico (Just "programming-in-haskell") "Programming in Haskell" [("Graham Hutton", britanica)] (Just 2007) 1
    , tecnico (Just "learn-you-a-haskell") "Learn You a Haskell for Great Good!" [("Miran Lipovača", Nothing)] (Just 2011) 1
    , tecnico Nothing "Haskell: Uma Introdução à Programação Funcional"
        [("Alexandre Garcia de Oliveira", brasileira)] Nothing 2
    , tecnico (Just "codigo-limpo") "Código Limpo" [("Robert C. Martin", estadunidense)] (Just 2008) 2
    , tecnico (Just "o-programador-pragmatico") "O Programador Pragmático" [("Andrew Hunt", Nothing), ("David Thomas", Nothing)] (Just 1999) 1
    , tecnico (Just "padroes-de-projeto") "Padrões de Projeto"
        [("Erich Gamma", Nothing), ("Richard Helm", Nothing), ("Ralph Johnson", Nothing), ("John Vlissides", Nothing)]
        (Just 1994) 1
    , tecnico (Just "entendendo-algoritmos") "Entendendo Algoritmos" [("Aditya Bhargava", Nothing)] (Just 2016) 2
    , tecnico (Just "algoritmos-teoria-e-pratica") "Algoritmos: Teoria e Prática"
        [("Thomas H. Cormen", estadunidense), ("Charles E. Leiserson", estadunidense), ("Ronald L. Rivest", estadunidense), ("Clifford Stein", estadunidense)]
        (Just 1990) 1
    ]
  where
    romance = dominioPublico "Romance"
    contos = dominioPublico "Contos"
    poesia = dominioPublico "Poesia"
    dominioPublico categoria arquivo t autores ano =
        LivroExtra t autores ano categoria gutenbergEditora (arquivo >>= capa)
    ficcao arquivo t autores ano = LivroExtra t autores (Just ano) "Ficção científica" (Just ("Aleph", Just "São Paulo")) (arquivo >>= capa)
    tecnico arquivo t autores ano = LivroExtra t autores ano "Técnico" Nothing (arquivo >>= capa)
    gutenbergEditora = Just ("Project Gutenberg", Nothing)
    capa :: Text -> Maybe Text
    capa arquivo = Just ("/capas/" <> arquivo <> ".jpg")
    brasileira = Just "Brasileira"
    portuguesa = Just "Portuguesa"
    britanica = Just "Britânica"
    estadunidense = Just "Estadunidense"
    machado = ("Machado de Assis", brasileira)
    alencar = ("José de Alencar", brasileira)
    eca = ("Eça de Queirós", portuguesa)
    camilo = ("Camilo Castelo Branco", portuguesa)
    asimov = ("Isaac Asimov", Just "Estadunidense")
