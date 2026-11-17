import "server-only";
import { cookies } from "next/headers";

export const COOKIE_SESSAO = "sessao";

export type Papel = "bibliotecario" | "socio";
export type Usuario = { login: string; papel: Papel };
export type Sessao = { token: string; expiraEm: string; usuario: Usuario };

export class ErroApi extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly campos: Record<string, string> = {},
  ) {
    super(message);
  }
}

function urlDaApi(caminho: string) {
  return `${process.env.API_URL ?? "http://localhost:3000"}${caminho}`;
}

export async function api<T>(caminho: string, init: RequestInit = {}): Promise<T> {
  const token = (await cookies()).get(COOKIE_SESSAO)?.value;
  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body) headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const resposta = await fetch(urlDaApi(caminho), { ...init, headers, cache: "no-store" });
  if (resposta.status === 204) return undefined as T;
  const corpo = await resposta.json().catch(() => ({}));
  if (!resposta.ok) {
    throw new ErroApi(resposta.status, corpo.erro ?? "A API respondeu com erro.", corpo.campos ?? {});
  }
  return corpo as T;
}

export async function usuarioAtual(): Promise<Usuario | null> {
  if (!(await cookies()).has(COOKIE_SESSAO)) return null;
  try {
    return await api<Usuario>("/api/eu");
  } catch (erro) {
    if (erro instanceof ErroApi && erro.status === 401) return null;
    throw erro;
  }
}

export function inicioDoPapel(papel: Papel) {
  return papel === "bibliotecario" ? "/painel" : "/";
}
