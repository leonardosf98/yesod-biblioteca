# Postman

Coleção com as rotas da API Yesod e dois ambientes.

| Arquivo | O que é |
|---|---|
| `biblioteca.postman_collection.json` | Requisições por pasta: Sessão, Catálogo, Sócio, Notificações, Balcão, Sócios, Acervo e Cadastros |
| `local.postman_environment.json` | API rodando com `stack exec biblioteca` em `http://localhost:3000` |
| `servidor.postman_environment.json` | API do servidor por túnel SSH em `http://localhost:3100` |

## Como usar

1. No Postman, **Import** e arraste os três arquivos.
2. Escolha o ambiente e preencha `senhaBibliotecario` e `senhaSocio` (são do tipo secreto e ficam vazias no repositório).
3. Rode **Sessão → Entrar como bibliotecário** e **Entrar como sócio**. Os tokens vão para `tokenBibliotecario` e `tokenSocio`, e cada pasta usa o do seu perfil.
4. As requisições que criam algo guardam o id devolvido (`livroId`, `pedidoId`, `emprestimoId`, `socioId`...) no ambiente, então dá para seguir um fluxo em ordem: pedir para retirar (sócio), confirmar a retirada (balcão), devolver.

## Servidor

A API não fica exposta na internet; o Caddy só encaminha para o Next. No servidor ela escuta só em `127.0.0.1:3000`, e o acesso é por túnel:

```bash
ssh -i ~/.ssh/biblioteca -N -L 3100:localhost:3000 ubuntu@<IP>
```

Com o túnel aberto, use o ambiente **Servidor (túnel SSH)**.

## Pela linha de comando

```bash
npx newman run postman/biblioteca.postman_collection.json \
  -e postman/local.postman_environment.json \
  --env-var senhaBibliotecario=... --env-var senhaSocio=... \
  --folder "Sessão" --folder "Catálogo"
```
