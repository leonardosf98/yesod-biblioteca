# História 001 — Frontend em Next.js com área do bibliotecário e área do sócio

**Como** bibliotecário, **quero** um painel moderno para cuidar do acervo, dos sócios e do balcão de empréstimos;
**como** sócio, **quero** entrar no site, achar um livro e pedir o empréstimo sozinho;
**para que** a biblioteca deixe de depender do balcão para tudo e o sistema pareça um produto, não um formulário.

Ponto de partida: tag `v1.0.0` (monolito Yesod com Hamlet). Ela continua sendo a versão estável até esta história fechar.

## O que muda na arquitetura

O projeto passa da Opção A (monolito com Shakespearean Templates) para a **Opção B** do enunciado: Yesod como API REST + frontend separado. O backend continua obrigatoriamente em Yesod; as regras (`src/Regras/*`) e as integrações (`src/Integracao/*`) são reaproveitadas sem mudança.

```
Navegador ──> Next.js (Vercel) ──server-to-server──> API Yesod (Lightsail) ──> Postgres (Supabase)
                 │                                      ├─ Open Library
                 └─ cookie httpOnly com o token         └─ ViaCEP
```

- **Next.js como BFF**: o navegador só fala com o Next.js; o Next.js chama a API pelo servidor (Server Components, Server Actions e Route Handlers). Assim a API não precisa de CORS nem de cookie entre domínios, e o token nunca chega ao JavaScript do navegador.
- **Repositório**: monorepo. O Yesod fica na raiz (CI, Docker e testes já estão aí) e o frontend entra em `web/`.
- **Deploy**: o Next.js vai bem na Vercel; a API vai em container no Lightsail; o banco no Supabase.

## Autenticação e papéis

| Papel | Como entra | O que pode |
|---|---|---|
| Visitante | — | Ver o catálogo |
| Sócio | E-mail e senha | Catálogo, pedir empréstimo, reservar, renovar, ver os próprios empréstimos e editar o perfil |
| Bibliotecário | Login e senha | Tudo, incluindo cadastros, balcão e relatórios |

- Senhas com hash (`password`/bcrypt, como no `yesod-auth-hashdb`).
- `POST /api/sessoes` devolve um token opaco aleatório; o banco guarda só o hash do token, com validade. `DELETE /api/sessoes` encerra.
- `isAuthorized` decide por papel e por rota; o sócio só enxerga os próprios dados (checado no handler, não só na rota).
- Modelo: `User` ganha `papel` (`Bibliotecario | Socio`); `Socio` ganha `userId` opcional (sócio cadastrado no balcão pode ativar o acesso depois); nova tabela `Sessao` (userId, hash do token, expira em).

## Empréstimo pelo sócio

O livro é físico, então o pedido do sócio separa um exemplar e o empréstimo começa na retirada:

1. Sócio pede o livro → o sistema separa um exemplar disponível (mesma reserva atômica de hoje) e cria o empréstimo com status **Aguardando retirada**, válido por 48 h.
2. Bibliotecário confirma a retirada no balcão → status **Em andamento**, prazo de 14 dias a partir daí.
3. Passadas 48 h sem retirada → **Expirado**, exemplar liberado (verificado ao listar e ao pedir, sem precisar de job agendado).
4. Sem exemplar disponível → o botão vira **Entrar na fila** (reserva, como hoje).
5. Sócio pode **renovar uma vez** por mais 7 dias se não houver fila para o livro.

`Emprestimo` ganha `status` e `dataLimiteRetirada`; as regras continuam em `src/Regras/Emprestimo.hs`, com testes.

## API REST (Yesod, JSON)

| Método | Rota | Quem | Para quê |
|---|---|---|---|
| POST / DELETE | `/api/sessoes` | todos | Entrar e sair |
| GET | `/api/livros?busca=&categoria=` | público | Catálogo com capa, autores e disponibilidade |
| GET | `/api/livros/:id` | público | Detalhe com exemplares disponíveis |
| POST | `/api/livros/:id/pedidos` | sócio | Pedir empréstimo |
| POST | `/api/livros/:id/reservas` | sócio | Entrar na fila |
| GET | `/api/eu` · `/api/eu/emprestimos` · `/api/eu/reservas` | sócio | Perfil e histórico |
| POST | `/api/eu/emprestimos/:id/renovacao` | sócio | Renovar |
| GET/POST/PUT/DELETE | `/api/{livros,autores,editoras,categorias,exemplares,socios}` | bibliotecário | Cadastros |
| POST | `/api/livros/importacao` | bibliotecário | Importar por ISBN (Open Library) |
| POST | `/api/emprestimos/:id/{retirada,devolucao}` | bibliotecário | Balcão |
| GET | `/api/painel` | bibliotecário | Contadores, atrasados, retiradas pendentes |

Erros em JSON com status coerente (400 validação com erros por campo, 401, 403, 404, 409 conflito de ISBN/e-mail/exemplar). A documentação curta dos endpoints entra no README, como o enunciado pede para a Opção B.

## Frontend (Next.js) e repaginação

- Next.js (App Router, TypeScript), Tailwind e uma biblioteca de componentes acessível; pacotes conferidos no registry antes de instalar.
- **Área do sócio** (`/`): vitrine com capas grandes (vindas da Open Library), busca instantânea, filtros por categoria, página do livro com disponibilidade e botão Pedir / Entrar na fila, "Meus empréstimos" com prazo, multa prevista e renovação, perfil com CEP.
- **Área do bibliotecário** (`/painel`): dashboard com contadores e listas de atrasados e retiradas pendentes, balcão (confirmar retirada, registrar devolução com multa), cadastros em tabelas com busca e edição em painel lateral, importação por ISBN com pré-visualização da capa.
- Identidade visual própria (tipografia, paleta, modo escuro), responsivo para celular, estados de carregamento e vazio, mensagens de erro vindas da API.

## Fatias (uma PR cada, até ~400 linhas)

| # | Fatia | Entrega |
|---|---|---|
| 1 | CI completo | hlint, Semgrep, auditoria de dependências pela OSV, testes, pr-risk-tier |
| 2 | Papéis e sessões | `User.papel`, `Sessao`, `POST/DELETE /api/sessoes`, `isAuthorized` por papel |
| 3 | API do catálogo | `GET /api/livros` e detalhe, JSON com disponibilidade |
| 4 | Pedido pelo sócio | status do empréstimo, retirada, expiração, renovação, endpoints `/api/eu/*` |
| 5 | API de cadastros | CRUD JSON das entidades e importação por ISBN |
| 6 | Esqueleto do `web/` | Next.js, design system, layout das duas áreas, login via BFF, CI do frontend |
| 7 | Área do sócio | vitrine, detalhe, pedir/reservar, meus empréstimos, perfil |
| 8 | Painel do bibliotecário | dashboard, balcão, cadastros, importação |
| 9 | Deploy | API no Lightsail, Next.js na Vercel, banco no Supabase |
| 10 | Desligar o Hamlet | remover as páginas antigas quando o Next.js cobrir tudo; README da Opção B |

## Critérios de aceite

- Sócio cria conta (ou ativa a criada no balcão), entra, acha um livro, pede, e o bibliotecário confirma a retirada; o exemplar some da disponibilidade no catálogo no mesmo instante.
- Sócio não vê nem altera dados de outro sócio (testado na API).
- Todas as regras atuais continuam valendo e testadas: limite de 3, multa, exemplar perdido, fila de reservas.
- Telas do sócio usáveis no celular.
- CI verde com SAST e auditoria de dependências; a `v1.0.0` segue disponível como fallback.

## Em aberto

- Sócio pode se cadastrar sozinho ou só ativar conta criada no balcão?
- O pedido expira em 48 h — o prazo serve?
- Multa pendente bloqueia novos pedidos do sócio?
- Manter o Hamlet como plano B depois da fatia 10 ou apagar de vez (menos código para explicar na arguição)?
