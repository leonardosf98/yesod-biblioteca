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
export type Catalogo = {
  livros: LivroResumo[];
  categorias: Categoria[];
  pagina: number;
  porPagina: number;
  total: number;
  paginas: number;
};

export function buscarCatalogo(filtros: { busca?: string; categoria?: string; situacao?: string; pagina?: string; porPagina?: number }) {
  const parametros = new URLSearchParams();
  if (filtros.busca) parametros.set("busca", filtros.busca);
  if (filtros.categoria) parametros.set("categoria", filtros.categoria);
  if (filtros.situacao) parametros.set("situacao", filtros.situacao);
  if (filtros.pagina) parametros.set("pagina", filtros.pagina);
  if (filtros.porPagina) parametros.set("porPagina", String(filtros.porPagina));
  const consulta = parametros.size ? `?${parametros}` : "";
  return api<Catalogo>(`/api/livros${consulta}`);
}

export type LivroDetalhe = {
  id: number;
  titulo: string;
  isbn: string | null;
  ano: number | null;
  sinopse: string | null;
  capaUrl: string | null;
  editora: string | null;
  editoraId: number | null;
  categoria: Categoria;
  autores: { id: number; nome: string }[];
  exemplares: { id: number; codigo: string; estado: "bom" | "danificado" | "perdido"; disponivel: boolean }[];
  disponiveis: number;
  fila: number;
};

export function buscarLivro(id: string) {
  return api<LivroDetalhe>(`/api/livros/${encodeURIComponent(id)}`);
}
