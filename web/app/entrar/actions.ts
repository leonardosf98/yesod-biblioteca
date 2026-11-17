"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { api, COOKIE_SESSAO, inicioDoPapel } from "@/lib/api";
import { iniciarSessao } from "@/lib/sessao";

export type EstadoLogin = { erro?: string; login?: string };

export async function entrar(_anterior: EstadoLogin, dados: FormData): Promise<EstadoLogin> {
  const login = String(dados.get("login") ?? "").trim();
  const senha = String(dados.get("senha") ?? "");
  if (!login || !senha) return { erro: "Informe login e senha.", login };

  const resultado = await iniciarSessao(login, senha);
  if ("erro" in resultado) return { erro: resultado.erro, login };
  redirect(inicioDoPapel(resultado.papel));
}

export async function sair() {
  await api("/api/sessoes", { method: "DELETE" }).catch(() => undefined);
  (await cookies()).delete(COOKIE_SESSAO);
  redirect("/entrar");
}
