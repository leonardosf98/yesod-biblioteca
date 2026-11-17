import "server-only";
import { api, ErroApi } from "@/lib/api";

type Ref = { id: number; nome: string };
type LivroCurto = { id: number; titulo: string; capaUrl: string | null };

export type EmprestimoPainel = {
  emprestimoId: number;
  socio: Ref;
  livro: LivroCurto;
  exemplar: string | null;
  dataPrevista: string;
  diasAtraso: number;
  multaCentavos: number;
};
export type PedidoPainel = {
  id: number;
  codigo: string;
  socio: Ref;
  livro: LivroCurto;
  exemplar: string | null;
  criadoEm: string;
  limiteRetirada: string;
};
export type Painel = {
  resumo: { abertos: number; exemplares: number; pedidos: number; atrasados: number; multaAtrasadosCentavos: number; devolucoesHoje: number };
  pedidos: PedidoPainel[];
  atrasados: EmprestimoPainel[];
  devolucoesHoje: EmprestimoPainel[];
};
export type SocioBalcao = { id: number; nome: string; email: string; cidade: string | null; emUso: number; pendencias: string[]; contaAtiva: boolean };
export type ConsultaExemplar = {
  exemplar: { id: number; codigo: string; estado: string; disponivel: boolean };
  livro: { id: number; titulo: string | null; capaUrl: string | null };
  emprestimo: { id: number; socio: Ref; dataPrevista: string; multaCentavos: number } | null;
};

export const buscarPainel = () => api<Painel>("/api/painel");

export function buscarSocios(busca: string) {
  return api<{ socios: SocioBalcao[]; limite: number }>(`/api/socios?busca=${encodeURIComponent(busca)}`);
}

export async function consultarExemplar(codigo: string): Promise<ConsultaExemplar | null> {
  try {
    return await api<ConsultaExemplar>(`/api/balcao/exemplares/${encodeURIComponent(codigo)}`);
  } catch (erro) {
    if (erro instanceof ErroApi && erro.status === 404) return null;
    throw erro;
  }
}
