# ROADMAP — Biblioteca Comunitária (Yesod / Haskell)

Projeto final da disciplina: aplicação web em Yesod com 7+ tabelas, CRUD, uma API externa, README e arguição individual. A arguição vale 8 dos 10 pontos.

## Decisões

| Tema | Escolha | Por quê |
|---|---|---|
| Arquitetura | **Opção A — monolítica** (Yesod + Hamlet/Lucius) | Um só projeto e um só deploy. Rotas, handlers e templates ficam no mesmo lugar, e a arguição cobra exatamente isso |
| Banco | **PostgreSQL** (`persistent-postgresql`) | Relacional "de verdade" e já temos um Supabase para hospedar. Em dev, roda via Docker |
| Domínio | **Biblioteca comunitária**: acervo, sócios, empréstimos, reservas | As 7+ tabelas saem do próprio domínio, sem nenhuma artificial |
| APIs externas | **Open Library** (busca por ISBN) e **ViaCEP** (endereço do sócio) | Os dados recebidos são gravados e usados, não só consultados |
| Build | `stack` + template `yesodweb/postgres` (lts-20.26, GHC 9.2.8) | O scaffold já vem com Persistent, formulários, sessão e testes configurados |
| Hospedagem (opcional) | Render ou Fly.io + Postgres no Supabase | Conta como diferencial na apresentação |

## Modelo de dados (9 tabelas)

| Tabela | Campos principais | Relacionamentos |
|---|---|---|
| `Autor` | nome, nacionalidade | N:N com Livro |
| `Editora` | nome, cidade | 1:N com Livro |
| `Categoria` | nome (único), descricao | 1:N com Livro |
| `Livro` | titulo, isbn (único), ano, sinopse, capaUrl | FK editora, FK categoria |
| `LivroAutor` | — | FK livro, FK autor (tabela de junção, PK composta) |
| `Exemplar` | codigo (único), estado (bom/danificado/perdido), disponivel | FK livro |
| `Socio` | nome, email (único), telefone, cep, logradouro, numero, bairro, cidade, uf | — |
| `Emprestimo` | dataEmprestimo, dataPrevista, dataDevolucao (nula até a devolução), multaCentavos (inteiro, evita erro de arredondamento) | FK exemplar, FK socio |
| `Reserva` | dataReserva, status (ativa/atendida/cancelada) | FK livro, FK socio |

Todas as FKs são `ON DELETE RESTRICT`, menos `LivroAutor → Livro` (`CASCADE`): o próprio banco impede apagar o que ainda é referenciado.

Regras de negócio: exemplar emprestado fica indisponível; não dá para excluir um livro que tem exemplares ou reservas (o histórico de empréstimos depende deles); a multa é calculada por dia de atraso; um sócio só pode ter até 3 empréstimos abertos.

## Divisão sugerida (até 4 integrantes, mínimo de 3 commits relevantes cada)

| Integrante | Frente |
|---|---|
| A | Setup, modelo de dados, Autor/Editora/Categoria |
| B | Livro + LivroAutor + integração com a Open Library |
| C | Socio + integração com o ViaCEP + Exemplar |
| D | Empréstimo/Reserva (regras de negócio), layout, README e deploy |

Cada pessoa abre a própria branch (`feat/<frente>`) e faz PR para `main`, commitando **com a própria conta do GitHub**.

---

## Fase 0 — Ambiente e repositório
- [x] 0.1 Criar o repositório no GitHub: público, em https://github.com/leonardosf98/yesod-biblioteca
- [x] 0.2 Gerar o scaffold: `stack new biblioteca yesodweb/postgres` e mover para a raiz do repo
- [x] 0.3 `docker-compose.yml` com Postgres 16 na porta 5433 do host (a 5432 costuma estar ocupada), banco `biblioteca` + `biblioteca_test`
- [x] 0.4 Rodar `stack build` e `stack exec biblioteca` (ou `yesod devel`) e abrir em `localhost:3000`
- [x] 0.5 `.gitignore` (`.stack-work/`, `static/tmp/`, `.env`), mais um `.env.example`
- [x] 0.6 Limpar o scaffold: remover o `Comment` e a página de exemplo e manter o `User`, se usarmos autenticação
- [x] 0.7 Primeiro commit e configuração da proteção da `main` (PR obrigatório)
- [ ] 0.8 CI no GitHub Actions: `stack build` + `stack test` com Postgres como service e cache de `~/.stack`
- [ ] 0.9 Pacote de evidências por PR com `leonardosf98/pr-risk-tier@v1` e regras em `.github/pr-risk-tier.toml` (docs = 0, padrão = 1, modelo/rotas/integrações = 2, Foundation/config/build/CI = 3)

## Fase 1 — Modelo de dados
- [x] 1.1 Escrever as 9 entidades em `config/models.persistentmodels`, com `UniqueIsbn`, `UniqueSocioEmail`, `UniqueCodigo` e PK composta em `LivroAutor` (`UniqueEmail` já é do scaffold)
- [x] 1.2 Tipos derivados para os enums `EstadoExemplar` e `StatusReserva` (`derivePersistField`, em `src/Model/Tipos.hs`)
- [x] 1.3 Conferir a migração automática (`runMigration migrateAll`) e as FKs criadas no Postgres (`\d livro`)
- [x] 1.4 Seed idempotente em `src/Seed.hs`, executável `stack exec biblioteca-seed`, com testes em `test/SeedSpec.hs`
- [ ] 1.5 Desenhar o diagrama ER simples (opcional, ajuda na arguição)

## Fase 2 — Layout e navegação
- [x] 2.1 `templates/default-layout.hamlet` com marca e menu; cada fase de CRUD acrescenta seu item (Livros, Autores, Editoras, Categorias, Sócios, Empréstimos, Reservas) em `Foundation.hs`, porque o link só compila quando a rota existe
- [x] 2.2 Estilo base em `default-layout.lucius` (ou Bootstrap, que já vem no scaffold)
- [x] 2.3 Mensagens com status via `addMessage "success"|"danger"|"warning"` e `getMessages` (vira `alert-<status>` do Bootstrap)
- [x] 2.4 Página inicial (`HomeR`) com contadores: livros, exemplares disponíveis, empréstimos atrasados

## Fase 3 — CRUDs simples (Autor, Editora, Categoria — 1 PR por entidade)
Para cada entidade, seguir este padrão de rotas em `config/routes.yesodroutes`:
```
/autores              AutoresR      GET POST
!/autores/novo        AutorNovoR    GET
/autores/#AutorId     AutorR        GET POST
/autores/#AutorId/editar  AutorEditarR GET
/autores/#AutorId/excluir AutorExcluirR POST
```
- [x] 3.1 Autor: formulário `AForm` com validação (nome obrigatório, tamanho máximo), listagem, edição e exclusão
- [x] 3.0 Proteção CSRF em todo POST (`defaultCsrfMiddleware`) e mensagens de validação em português (`portugueseFormMessage`)
- [x] 3.2 Editora: mesmo padrão, com nome único (`insertUnique` no cadastro; na edição, `getBy` na chave única e recusa se for outro registro)
- [x] 3.3 Categoria: mesmo padrão, com tratamento do erro de nome duplicado (`insertUnique`)
- [x] 3.4 Bloquear a exclusão quando houver livros vinculados, com mensagem amigável
- [x] 3.5 Helpers comuns em `src/Form/Comum.hs`: `textoLimitado` (obrigatório, sem espaços nas pontas, tamanho máximo), `paginaFormulario`, `botaoExcluir` (POST com token CSRF) e `mensagem`

## Fase 4 — Livros + Open Library (2 PRs: 4a CRUD, 4b integração)
- [x] 4a.1 CRUD de Livro com selects de Editora e Categoria (`selectField` + `optionsPersistKey`)
- [x] 4a.2 Multiselect de autores, gravando em `LivroAutor` (no update, apagar e reinserir na mesma transação)
- [x] 4a.3 Página de detalhe: autores, exemplares, disponibilidade e capa
- [x] 4b.4 Módulo `Integracao/OpenLibrary.hs`: `GET https://openlibrary.org/api/books?bibkeys=ISBN:<isbn>&format=json&jscmd=data` com `http-conduit` + `aeson`; incluir `src/Integracao/**` na regra de tier 2 do `.github/pr-risk-tier.toml`
- [x] 4b.5 Botão "Buscar por ISBN" que preenche título, ano, sinopse e capa, cria a editora e os autores que ainda não existem e salva tudo
- [x] 4b.6 Tratar ISBN inexistente, timeout e JSON inesperado (`Either`/`Maybe`), mostrando a mensagem ao usuário sem derrubar a página
- [x] 4a.7 Busca e filtro na listagem: título com `ILIKE` (filtro específico do Postgres via `BackendSpecificFilter`) e categoria

## Fase 5 — Exemplares
- [x] 5.1 CRUD de Exemplar a partir da página do livro (`/livros/#LivroId/exemplares/novo`, `/exemplares/#ExemplarId/editar`)
- [x] 5.2 Código único informado ou gerado (`L<livro>-<n>`), estado via `optionsEnum`; a disponibilidade não está no formulário porque quem muda é o empréstimo
- [x] 5.3 Impedir a exclusão de exemplar com qualquer empréstimo registrado (o histórico depende dele); a saída é marcar como Perdido

## Fase 6 — Sócios + ViaCEP
- [ ] 6.1 CRUD de Sócio com validação de e-mail, telefone e CEP (8 dígitos)
- [ ] 6.2 Módulo `Integracao/ViaCep.hs`: `GET https://viacep.com.br/ws/<cep>/json/`
- [ ] 6.3 Ao salvar (ou num botão "Buscar CEP"), preencher logradouro, bairro, cidade e UF e persistir
- [ ] 6.4 Tratar `{"erro": true}` (CEP inexistente) e falhas de rede
- [ ] 6.5 Detalhe do sócio com o histórico de empréstimos e as reservas

## Fase 7 — Empréstimos e reservas (2 PRs: 7a empréstimo, 7b reserva)
- [ ] 7.1 Novo empréstimo: escolher o sócio e um exemplar disponível; `dataPrevista` = hoje + 14 dias
- [ ] 7.2 Validar o limite de 3 empréstimos abertos por sócio e se o exemplar está disponível (tudo em `runDB`, na mesma transação)
- [ ] 7.3 Devolução: grava `dataDevolucao`, calcula a multa (R$ 1,00/dia de atraso) e libera o exemplar
- [ ] 7.4 Listagem com filtros: abertos, atrasados e devolvidos (consulta com `E.innerJoin` via Esqueleto ou `selectList` + joins manuais)
- [ ] 7.5 Editar e excluir empréstimo (excluir só se ainda não foi devolvido, e nesse caso liberar o exemplar)
- [ ] 7.6 Reserva: criar para um livro sem exemplar disponível; cancelar; marcar como atendida quando o empréstimo é criado
- [ ] 7.7 Ao devolver, avisar se existe reserva ativa para aquele livro

## Fase 8 — Qualidade e tratamento de erros
- [ ] 8.1 Páginas 404/500 personalizadas (`errorHandler` em `Foundation.hs`)
- [ ] 8.2 Validações de formulário com mensagens em português
- [ ] 8.3 Testes com `yesod-test` para pelo menos um CRUD e para a regra de empréstimo
- [ ] 8.4 Revisar a organização: `Handler/<Entidade>.hs`, `Integracao/*.hs`, `Form/*.hs`
- [ ] 8.5 `hlint` e build sem warnings

## Fase 9 — Autenticação (opcional, diferencial)
- [ ] 9.1 Login de bibliotecário com `yesod-auth` (`Auth.HashDB` ou e-mail)
- [ ] 9.2 Proteger rotas de escrita via `isAuthorized`

## Fase 10 — Hospedagem (opcional)
- [ ] 10.1 `Dockerfile` multi-stage (build com stack, runtime enxuto); incluir `Dockerfile` na regra de tier 3 do `.github/pr-risk-tier.toml`
- [ ] 10.2 Usar o Postgres do Supabase (Session pooler, IPv4, `sslmode=require`) e configurar `YESOD_PGHOST`/`YESOD_PGPORT`/`YESOD_PGUSER`/`YESOD_PGPASS`/`YESOD_PGDATABASE` no serviço
- [ ] 10.3 Deploy no Render/Fly.io e teste do fluxo completo na URL pública
- [ ] 10.4 Rodar o seed no ambiente hospedado

## Fase 11 — README.md (curto, exigido pelo enunciado)
- [ ] 11.1 Descrição: nome, objetivo e funcionalidades
- [ ] 11.2 Tecnologias: Yesod, Persistent, PostgreSQL, Stack, Docker
- [ ] 11.3 Como executar: dependências, `docker compose up -d`, `stack build`, `stack exec -- yesod devel`
- [ ] 11.4 Estrutura do banco: as 9 tabelas em uma linha cada
- [ ] 11.5 APIs: Open Library e ViaCEP, para que servem e onde são usadas
- [ ] 11.6 Integrantes e principais contribuições
- [ ] 11.7 Link da aplicação hospedada (se houver)

## Fase 12 — Entrega e preparação para a arguição (8 pts)
- [ ] 12.1 Conferir que cada integrante tem 3 ou mais commits relevantes com a própria conta (`git shortlog -sne`)
- [ ] 12.2 Roteiro da demo: CRUD de livro → busca por ISBN → sócio com CEP → empréstimo → devolução com multa → reserva
- [ ] 12.3 Cada integrante sabe explicar:
  - [ ] fluxo de uma requisição: `routes` → `mkYesod` → handler → `runDB` → widget/Hamlet
  - [ ] `models.persistentmodels`, chaves, FKs e como o Persistent gera tipos (`Entity`, `Key`)
  - [ ] formulários (`AForm`/`MForm`, `runFormPost`, CSRF)
  - [ ] interpolação no Hamlet (`#{}`, `@{}`, `^{}`) e o Lucius
  - [ ] integração HTTP + `FromJSON` e o tratamento de erro
  - [ ] regras do empréstimo e por que elas rodam em transação
- [ ] 12.4 Treinar uma alteração ao vivo (ex.: adicionar um campo numa entidade e exibi-lo na listagem)
- [ ] 12.5 Enviar o link do repositório (e do deploy) ao professor
