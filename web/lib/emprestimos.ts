import "server-only";
import { api } from "@/lib/api";

type LivroCurto = { id: number; titulo: string; capaUrl: string | null };

export type Emprestimo = {
  id: number;
  livro: LivroCurto;
  exemplar: string | null;
  dataEmprestimo: string;
  dataPrevista: string;
  dataDevolucao: string | null;
  atrasado: boolean;
  renovacoes: number;
  multaCentavos: number;
  multaPaga: boolean;
};
export type Pedido = { id: number; codigo: string; livro: LivroCurto; limiteRetirada: string };
export type Reserva = { id: number; livro: LivroCurto; posicao: number };
export type MeusEmprestimos = {
  emprestimos: Emprestimo[];
  pedidos: Pedido[];
  reservas: Reserva[];
  pendencias: string[];
  emUso: number;
  limite: number;
};

export function buscarMeusEmprestimos() {
  return api<MeusEmprestimos>("/api/eu/emprestimos");
}
