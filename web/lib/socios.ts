import "server-only";
import { api } from "@/lib/api";

export type SocioDetalhe = {
  id: number;
  nome: string;
  email: string;
  telefone: string | null;
  cep: string | null;
  logradouro: string | null;
  numero: string | null;
  bairro: string | null;
  cidade: string | null;
  uf: string | null;
  contaAtiva: boolean;
  pendencias: string[];
  emprestimos: { id: number; livro: string | null; exemplar: string | null; dataEmprestimo: string; dataPrevista: string; dataDevolucao: string | null; multaCentavos: number; multaPaga: boolean }[];
  reservas: { id: number; livro: string | null }[];
};

export const buscarSocio = (id: string) => api<SocioDetalhe>(`/api/socios/${encodeURIComponent(id)}`);
