import "server-only";
import { api, ErroApi } from "@/lib/api";

export type Notificacao = {
  id: number;
  tipo: string;
  titulo: string;
  texto: string;
  link: string | null;
  criadaEm: string;
  lidaEm: string | null;
};
export type Notificacoes = { naoLidas: number; notificacoes: Notificacao[] };

const vazio: Notificacoes = { naoLidas: 0, notificacoes: [] };

export async function listarNotificacoes(limite = 20): Promise<Notificacoes> {
  try {
    return await api<Notificacoes>(`/api/notificacoes?limite=${limite}`);
  } catch (erro) {
    if (erro instanceof ErroApi && (erro.status === 404 || erro.status === 401)) return vazio;
    throw erro;
  }
}
