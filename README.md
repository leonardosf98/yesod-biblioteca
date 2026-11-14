# Biblioteca Comunitária

Aplicação web em Yesod (Haskell) para gestão de acervo, sócios, empréstimos e reservas. O planejamento está no [ROADMAP.md](ROADMAP.md).

## Como executar

Pré-requisitos: [Stack](https://docs.haskellstack.org/), Docker e a biblioteca cliente do Postgres (`sudo apt install libpq-dev` no Ubuntu/Debian).

```bash
docker compose up -d
stack build
stack exec biblioteca
```

A aplicação sobe em http://localhost:3000. O Postgres do Docker escuta na porta 5433 do host; para usar outro banco, defina as variáveis do `.env.example`.

Testes: `stack test` (usa o banco `biblioteca_test`, criado pelo container).

Para recarregar automaticamente ao editar: `stack install yesod-bin` e depois `stack exec -- yesod devel`.
