import "server-only";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { api, ErroApi } from "@/lib/api";

export type EstadoForm = { erro?: string; ok?: string; campos?: Record<string, string>; valores?: Record<string, string> };

export function valoresDe(dados: FormData) {
  return Object.fromEntries([...dados.entries()].filter(([, v]) => typeof v === "string")) as Record<string, string>;
}

export async function enviar(
  caminho: string,
  metodo: "POST" | "PUT" | "DELETE",
  dados: FormData,
  corpo: object | undefined,
  depois: { revalidar: string; destino?: (resposta: { id?: number }) => string; ok?: string },
): Promise<EstadoForm> {
  let resposta: { id?: number } = {};
  try {
    resposta = (await api<{ id?: number }>(caminho, { method: metodo, body: corpo ? JSON.stringify(corpo) : undefined })) ?? {};
  } catch (erro) {
    if (erro instanceof ErroApi) return { erro: erro.message, campos: erro.campos, valores: valoresDe(dados) };
    return { erro: "Não foi possível falar com o servidor.", valores: valoresDe(dados) };
  }
  revalidatePath(depois.revalidar, "layout");
  if (depois.destino) redirect(depois.destino(resposta));
  return { ok: depois.ok ?? "Salvo." };
}

export function texto(dados: FormData, nome: string) {
  const valor = String(dados.get(nome) ?? "").trim();
  return valor || null;
}
