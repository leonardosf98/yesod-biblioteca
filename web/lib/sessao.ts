import "server-only";
import { cookies } from "next/headers";
import { api, COOKIE_SESSAO, ErroApi, type Papel, type Sessao } from "@/lib/api";

export async function iniciarSessao(login: string, senha: string): Promise<{ papel: Papel } | { erro: string }> {
  let sessao: Sessao;
  try {
    sessao = await api<Sessao>("/api/sessoes", {
      method: "POST",
      body: JSON.stringify({ login, senha }),
    });
  } catch (erro) {
    if (erro instanceof ErroApi && erro.status === 401) return { erro: erro.message };
    return { erro: "Não foi possível falar com o servidor. Tente de novo em instantes." };
  }

  (await cookies()).set(COOKIE_SESSAO, sessao.token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    expires: new Date(sessao.expiraEm),
  });
  return { papel: sessao.usuario.papel };
}
