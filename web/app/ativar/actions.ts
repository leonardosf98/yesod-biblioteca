"use server";

import { redirect } from "next/navigation";
import { api, ErroApi } from "@/lib/api";
import { iniciarSessao } from "@/lib/sessao";

export type EstadoAtivacao = { erro?: string; email?: string; codigo?: string };

export async function ativar(_anterior: EstadoAtivacao, dados: FormData): Promise<EstadoAtivacao> {
  const email = String(dados.get("email") ?? "").trim().toLowerCase();
  const codigo = String(dados.get("codigo") ?? "").trim();
  const senha = String(dados.get("senha") ?? "");
  const confirmacao = String(dados.get("confirmacao") ?? "");
  const manter = { email, codigo };

  if (senha !== confirmacao) return { ...manter, erro: "As senhas não conferem." };

  try {
    await api("/api/ativacao", { method: "POST", body: JSON.stringify({ email, codigo, senha }) });
  } catch (erro) {
    if (erro instanceof ErroApi && erro.status === 400) return { ...manter, erro: erro.message };
    return { ...manter, erro: "Não foi possível falar com o servidor. Tente de novo em instantes." };
  }

  const resultado = await iniciarSessao(email, senha);
  redirect("erro" in resultado ? "/entrar" : "/");
}
