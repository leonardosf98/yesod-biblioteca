"use server";

import { revalidatePath } from "next/cache";
import { api, ErroApi } from "@/lib/api";
import type { ResultadoAcao } from "@/components/botao-acao";

async function executar(caminho: string, metodo: "POST" | "DELETE", ok: string): Promise<ResultadoAcao> {
  try {
    await api(caminho, { method: metodo });
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível falar com o servidor." };
  }
  revalidatePath("/", "layout");
  return { ok };
}

export async function pedir(livroId: number) {
  return executar(`/api/livros/${livroId}/pedidos`, "POST", "Pedido feito.");
}

export async function entrarNaFila(livroId: number) {
  return executar(`/api/livros/${livroId}/reservas`, "POST", "Você entrou na fila.");
}

export async function renovar(emprestimoId: number) {
  return executar(`/api/eu/emprestimos/${emprestimoId}/renovacao`, "POST", "Renovado por mais 7 dias.");
}

export async function cancelarPedido(pedidoId: number) {
  return executar(`/api/eu/pedidos/${pedidoId}`, "DELETE", "Pedido cancelado.");
}
