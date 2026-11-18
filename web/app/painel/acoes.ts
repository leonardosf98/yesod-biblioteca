"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { ResultadoAcao } from "@/components/botao-acao";
import { api, ErroApi } from "@/lib/api";
import { reais } from "@/lib/formato";

async function executar<T>(caminho: string, corpo: object | undefined, ok: (resposta: T) => string): Promise<ResultadoAcao> {
  try {
    const resposta = await api<T>(caminho, { method: "POST", body: corpo ? JSON.stringify(corpo) : undefined });
    revalidatePath("/painel", "layout");
    return { ok: ok(resposta) };
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível falar com o servidor." };
  }
}

export async function confirmarRetirada(pedidoId: number) {
  return executar<{ dataPrevista: string }>(`/api/pedidos/${pedidoId}/retirada`, undefined, () => "Retirada confirmada.");
}

export async function cancelarPedidoNoBalcao(pedidoId: number): Promise<ResultadoAcao> {
  try {
    await api(`/api/pedidos/${pedidoId}`, { method: "DELETE" });
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível falar com o servidor." };
  }
  revalidatePath("/painel", "layout");
  return { ok: "Pedido cancelado." };
}

export async function registrarEmprestimo(socioId: number, exemplarId: number, codigo: string): Promise<ResultadoAcao> {
  const resultado = await executar("/api/emprestimos", { socioId, exemplarId }, () => "");
  if (resultado.erro) return resultado;
  redirect(`/painel/balcao?${new URLSearchParams({ ok: "emprestimo", exemplar: codigo })}`);
}

export async function devolverNoBalcao(emprestimoId: number, codigo: string): Promise<ResultadoAcao> {
  let multa = 0;
  const resultado = await executar<{ multaCentavos: number }>(`/api/emprestimos/${emprestimoId}/devolucao`, undefined, (r) => {
    multa = r.multaCentavos;
    return "";
  });
  if (resultado.erro) return resultado;
  redirect(`/painel/balcao?${new URLSearchParams({ ok: "devolucao", devolver: codigo, multa: String(multa) })}`);
}

export async function registrarDevolucao(emprestimoId: number) {
  return executar<{ multaCentavos: number }>(`/api/emprestimos/${emprestimoId}/devolucao`, undefined, (r) =>
    r.multaCentavos > 0 ? `Devolução registrada com multa de ${reais(r.multaCentavos)}.` : "Devolução registrada, sem multa.",
  );
}
