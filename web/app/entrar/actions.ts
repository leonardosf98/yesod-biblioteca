"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { api, COOKIE_SESSAO, ErroApi, inicioDoPapel, type Sessao } from "@/lib/api";

export type EstadoLogin = { erro?: string; login?: string };

export async function entrar(_anterior: EstadoLogin, dados: FormData): Promise<EstadoLogin> {
  const login = String(dados.get("login") ?? "").trim();
  const senha = String(dados.get("senha") ?? "");
  if (!login || !senha) return { erro: "Informe login e senha.", login };

  let sessao: Sessao;
  try {
    sessao = await api<Sessao>("/api/sessoes", {
      method: "POST",
      body: JSON.stringify({ login, senha }),
    });
  } catch (erro) {
    if (erro instanceof ErroApi && erro.status === 401) return { erro: erro.message, login };
    return { erro: "Não foi possível falar com o servidor. Tente de novo em instantes.", login };
  }

  (await cookies()).set(COOKIE_SESSAO, sessao.token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    expires: new Date(sessao.expiraEm),
  });
  redirect(inicioDoPapel(sessao.usuario.papel));
}

export async function sair() {
  await api("/api/sessoes", { method: "DELETE" }).catch(() => undefined);
  (await cookies()).delete(COOKIE_SESSAO);
  redirect("/entrar");
}
