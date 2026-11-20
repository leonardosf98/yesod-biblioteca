# Guia do código

Para quem vai ler o projeto pela primeira vez: o que roda, onde fica cada coisa e o caminho de uma requisição do começo ao fim.

## O que roda

| Processo | Código | O que faz |
|---|---|---|
| `web` | `web/` (Next.js) | Telas do sócio e do bibliotecário. Fala com a API pelo servidor; o navegador nunca vê o token. |
| `api` | `app/main.hs` → `src/Application.hs` | API JSON em Yesod. Todas as regras de negócio. |
| `rotina` | `app/rotina.hs` → `src/Rotina.hs` | Roda a cada 5 minutos: expira pedidos, anda a fila de reservas e gera os avisos do sino. |
| `biblioteca-seed` | `app/seed.hs` → `src/Seed.hs` | Popula o banco com o acervo de exemplo. |
| `biblioteca-usuario` | `app/usuario.hs` | Cria ou troca a senha de um bibliotecário pelo terminal. |

Os quatro executáveis Haskell usam a mesma biblioteca (`src/`). Cada um é um `main` de poucas linhas em `app/`.

## Mapa das pastas

```
config/
  routes.yesodroutes        as URLs da API, agrupadas por área
  models.persistentmodels   as 14 tabelas; o Persistent gera os tipos Haskell e a migração
  settings.yml              porta, banco, logs (sobrescritos por variáveis de ambiente)

src/
  Application.hs            liga tudo: pool do Postgres, migração, servidor HTTP
  Foundation.hs             o tipo App, quem pode acessar cada rota, quem é o usuário da requisição
  Settings.hs               lê o settings.yml
  Model.hs, Model/Tipos.hs  entidades do banco e os enums (EstadoExemplar, Papel, StatusPedido…)
  Token.hs                  token de sessão, hash SHA-256 e códigos legíveis (AB-CD12)
  Rotina.hs                 o trabalho periódico da rotina
  Seed.hs                   dados de exemplo

  Handler/                  uma rota HTTP = uma função; um arquivo por área
    Sessao.hs               login, logout, "quem sou eu"
    Ativacao.hs             código de ativação e primeira senha do sócio
    Catalogo.hs             busca e detalhe de livros (público)
    Acervo.hs               cadastro de livros e exemplares, importação pelo ISBN
    Cadastros.hs            autores, editoras e categorias
    Socios.hs               cadastro e consulta de sócios
    Balcao.hs               o dia do bibliotecário: painel, empréstimo, devolução, retirada, multa
    AreaDoSocio.hs          o que o sócio faz: pedir, reservar, renovar, ver os empréstimos
    Notificacoes.hs         o sino: listar e marcar como lida

  Api/                      peças que os handlers repetem
    Validacao.hs            o tipo V, que valida o corpo JSON e junta os erros de todos os campos
    Resposta.hs             201, 204, 409 e "esse valor já existe"
    Filtro.hs               busca com ILIKE e parâmetros de query (?busca=, ?pagina=)
    Relacionados.hs         carrega de uma vez sócios, exemplares e livros ligados a uma lista

  Regras/                   regras de negócio; não sabem nada de HTTP
    Politica.hs             todos os números da biblioteca: prazos, limites, multa
    Emprestimo.hs           emprestar, devolver, renovar, multa, pendências
    Pedido.hs               pedir pela internet, retirar, cancelar, expirar, andar a fila
    Reserva.hs              entrar e sair da fila de reservas
    Conta.hs                ativação da conta do sócio e senha do bibliotecário
    Notificacao.hs          os textos dos avisos e a entrega para sócio ou bibliotecários
    Acervo.hs               ISBN, código do exemplar, gravar livro vindo da Open Library
    Socio.hs                telefone/CEP e endereço pelo ViaCEP
    Comum.hs                data de hoje, formatar R$, título do livro

  Integracao/               clientes HTTP das APIs externas
    OpenLibrary.hs          busca livro pelo ISBN
    ViaCep.hs               busca endereço pelo CEP

test/                       espelha src/: Handler/*Spec testa pela API, Regras/*Spec testa as regras direto
web/                        frontend Next.js (veja o fim deste guia)
deploy/, docker/            compose de produção, Caddy e Dockerfiles
```

### A regra de dependência

```
Handler  ──►  Regras  ──►  Model
   │             │
   ▼             ▼
  Api        Integracao
```

- **Handler** lê a requisição, chama uma regra dentro de `runDB` (uma transação) e monta o JSON.
- **Regras** recebem valores simples (`SocioId`, `Day`, `UTCTime`) e devolvem `Either Text resultado`: `Left` é o motivo da recusa, que o handler transforma em 409.
- Regras nunca importam Handler. Por isso dá para testá-las sem subir HTTP (`test/Regras/`).

## Uma requisição do começo ao fim

O sócio aperta "Pedir" na página de um livro.

1. **Next.js** (`web/app/(socio)/acoes.ts`) chama `POST /api/livros/7/pedidos` com o token do cookie no cabeçalho `Authorization`.
2. **Rota**: `config/routes.yesodroutes` liga essa URL ao construtor `LivroPedidosR 7`. O Yesod gera esse tipo a partir do arquivo, então uma URL errada é erro de compilação.
3. **Autorização**: antes do handler, o Yesod chama `isAuthorized` em `Foundation.hs`. `acessoDa` classifica a rota como `SomenteSocio`; `verificarAcesso` busca o usuário pelo token (`usuarioAtual`, com cache por requisição) e confere o papel. Sem token, 401; bibliotecário, 403.
4. **Handler**: `postLivroPedidosR` em `Handler/AreaDoSocio.hs` pega o sócio logado, a hora e a data, e roda dentro de uma transação:
   `runDB (get404 livroId >> pedirLivro socioId livroId agora dia)`
5. **Regra**: `pedirLivro` em `Regras/Pedido.hs`:
   - expira pedidos vencidos (`expirarPedidos`);
   - junta os impedimentos: multa em aberto, atraso, já ter 3 livros, já estar com esse livro;
   - se alguém está na frente na fila, recusa;
   - separa um exemplar livre com `UPDATE … WHERE disponivel = true` (duas pessoas ao mesmo tempo não pegam o mesmo);
   - grava o pedido com código e prazo de 48 h e avisa os bibliotecários.
   Devolve `Right pedido` ou `Left "motivo"`.
6. **Resposta**: `ouConflito` transforma `Left` em 409 com `{"erro": "motivo"}`; `Right` vira 201 com id, código e prazo.
7. **Erros inesperados**: `errorHandler` em `Foundation.hs` garante que 404, 401, 403 e 500 também saiam em JSON.

## Onde está cada regra

| Regra | Onde |
|---|---|
| Prazo de 14 dias, renovação de 7, limite de 3 livros, multa de R$ 1/dia, retirada em 48 h | `Regras/Politica.hs` |
| Multa e atraso bloqueiam novos pedidos e renovação | `pendencias` em `Regras/Emprestimo.hs` |
| Só renova uma vez, antes do prazo e sem fila | `renovarEmprestimo` em `Regras/Emprestimo.hs` |
| Fila de reservas: o primeiro sem pendência recebe o exemplar | `atenderFila` em `Regras/Pedido.hs` |
| Pedido não retirado em 48 h expira e passa para o próximo | `expirarPedidos` em `Regras/Pedido.hs` |
| Código de ativação vale 7 dias e aceita 5 tentativas | `Regras/Conta.hs` + `Regras/Politica.hs` |
| Avisos não duplicam se a rotina rodar de novo | chave única em `Regras/Notificacao.hs` |
| Quem pode acessar cada rota | `acessoDa` em `Foundation.hs` |

## O conteúdo da disciplina no código

| Conceito | Onde aparece |
|---|---|
| Tipos algébricos | `Model/Tipos.hs` (`EstadoExemplar`, `StatusPedido`), `Acesso` em `Foundation.hs`, `ErroAtivacao` em `Regras/Conta.hs` |
| `Maybe` | campos opcionais do banco (`isbn`, `dataDevolucao`), `campoTexto` em `Api/Validacao.hs` |
| `Either` para erro | toda regra que pode recusar devolve `Either Text a` |
| Funtor e aplicativo | o tipo `V` em `Api/Validacao.hs`: `Livro <$> texto … <*> opcional …` valida todos os campos e junta os erros |
| Mônadas e efeitos | `ReaderT SqlBackend m` nas regras (só banco), `Handler` nos handlers (HTTP + banco), `IO` nas integrações |
| Funções puras | `calcularMulta`, `normalizarIsbn`, `formatarCentavos`, os construtores de aviso em `Regras/Notificacao.hs` |
| Alta ordem | `forM_`, `mapM_`, `filter`, `maybe`, `either` por todo lado; `garantirUnico` recebe a chave única de qualquer tabela |
| Template Haskell | `models.persistentmodels` e `routes.yesodroutes` viram tipos na compilação |

## Quero mudar… onde mexo?

- **Um prazo, limite ou valor de multa** → `src/Regras/Politica.hs`.
- **O texto de um aviso do sino** → `src/Regras/Notificacao.hs`.
- **Uma rota nova** → linha em `config/routes.yesodroutes`, função no `Handler/` da área, regra em `Regras/` se houver decisão de negócio, permissão em `acessoDa` (`Foundation.hs`) se não for só do bibliotecário.
- **Um campo novo numa tabela** → `config/models.persistentmodels` (a migração roda sozinha ao subir), depois o `ler…` do handler e o JSON de resposta.
- **Uma validação de formulário** → a função `ler…` do handler, com as peças de `Api/Validacao.hs`.

## O frontend (`web/`)

```
web/lib/api.ts            a única porta para a API: põe o token do cookie e transforma erro em ErroApi
web/lib/sessao.ts         login: guarda o token num cookie httpOnly
web/lib/*.ts              um arquivo por área com os tipos das respostas e as chamadas GET
web/app/(socio)/          telas do sócio: catálogo, livro, meus empréstimos, avisos
web/app/painel/           telas do bibliotecário: painel, balcão, pedidos, sócios, acervo
web/app/**/acoes.ts       Server Actions: os POST/PUT/DELETE disparados por botões e formulários
web/components/           peças de tela reaproveitadas
```

As páginas rodam no servidor do Next, buscam os dados com `api()` e mandam HTML pronto. Os botões chamam Server Actions, que também rodam no servidor. Por isso o token nunca chega ao JavaScript do navegador.
