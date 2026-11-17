# História 002 — Notificações

**Como** sócio, **quero** ser avisado quando chega a minha vez na fila, quando um pedido está para expirar e quando uma devolução vence ou atrasa;
**como** bibliotecário, **quero** saber quando entra um pedido novo para separar;
**para que** ninguém dependa de abrir cada tela para descobrir o que mudou.

## Eventos

| Tipo (`tipo`) | Para quem | Quando nasce | Link sugerido |
|---|---|---|---|
| `fila_disponivel` | Sócio | Na devolução, quando o exemplar vai para o próximo da fila | `/emprestimos` |
| `pedido_expirando` | Sócio | Rotina: faltam 6 h para o pedido expirar | `/emprestimos` |
| `pedido_expirado` | Sócio | Rotina ou expiração do pedido | `/livros/{id}` |
| `pedido_cancelado` | Sócio | Bibliotecário cancela o pedido no painel | `/livros/{id}` |
| `devolucao_vencendo` | Sócio | Rotina: a devolução vence amanhã | `/emprestimos` |
| `emprestimo_atrasado` | Sócio | Rotina: uma vez por dia enquanto houver atraso, com a multa prevista no texto | `/emprestimos` |
| `pedido_novo` | Bibliotecários | Sócio faz um pedido | `/painel/pedidos` |

Os eventos por horário saem do executável `biblioteca-rotina` (uma passada e termina), chamado em loop por um serviço do compose. A tabela tem chave única por tipo + referência (empréstimo, pedido ou reserva) + dia, para a rotina poder rodar várias vezes sem repetir aviso.

## Contrato da API

Todas as rotas exigem `Authorization: Bearer <token>`; cada usuário só vê as próprias notificações.

### `GET /api/notificacoes`

Parâmetro opcional `limite` (padrão 20, máximo 100). Mais recentes primeiro.

```json
{
  "naoLidas": 2,
  "notificacoes": [
    {
      "id": 7,
      "tipo": "fila_disponivel",
      "titulo": "Chegou a sua vez: Dom Casmurro",
      "texto": "O exemplar DC-001 está separado para você até qui., 19 nov., 14:00.",
      "link": "/emprestimos",
      "criadaEm": "2026-11-17T17:00:00Z",
      "lidaEm": null
    }
  ]
}
```

- `naoLidas` conta todas as não lidas, não só as da página.
- `link` pode ser `null`.
- `tipo` desconhecido pelo front aparece com ícone genérico, então novos tipos não quebram nada.

### `POST /api/notificacoes/{id}/leitura`

Marca uma como lida. Responde `204`. Se a notificação for de outro usuário, `404`. Marcar de novo não muda `lidaEm`.

### `POST /api/notificacoes/leitura`

Marca todas do usuário como lidas. Responde `204`.

## Front (já implementado)

- Sino com contador no topo do site do sócio e no topo do painel; abre as 8 mais recentes.
- Página `/notificacoes` (sócio) e `/painel/notificacoes` (bibliotecário) com a lista completa e "Marcar todas como lidas".
- Clicar numa notificação marca como lida e abre o `link`.
- Enquanto `GET /api/notificacoes` responder `404`, o front mostra "Nenhuma notificação" em vez de erro.
