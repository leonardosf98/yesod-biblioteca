import "server-only";
import { api } from "@/lib/api";

export type Categoria = { id: number; nome: string };
export type LivroResumo = {
  id: number;
  titulo: string;
  ano: number | null;
  capaUrl: string | null;
  autores: string[];
  categoria: Categoria;
  disponiveis: number;
  fila: number;
};
export type Catalogo = { livros: LivroResumo[]; categorias: Categoria[] };

export function buscarCatalogo(filtros: { busca?: string; categoria?: string }) {
  const parametros = new URLSearchParams();
  if (filtros.busca) parametros.set("busca", filtros.busca);
  if (filtros.categoria) parametros.set("categoria", filtros.categoria);
  const consulta = parametros.size ? `?${parametros}` : "";
  return api<Catalogo>(`/api/livros${consulta}`);
}
