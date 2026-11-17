import "server-only";
import { api } from "@/lib/api";

export type Autor = { id: number; nome: string; nacionalidade: string | null; livros: number };
export type Editora = { id: number; nome: string; cidade: string | null; livros: number };
export type CategoriaAcervo = { id: number; nome: string; descricao: string | null; livros: number };

export const listarAutores = () => api<{ autores: Autor[] }>("/api/autores").then((r) => r.autores);
export const listarEditoras = () => api<{ editoras: Editora[] }>("/api/editoras").then((r) => r.editoras);
export const listarCategorias = () => api<{ categorias: CategoriaAcervo[] }>("/api/categorias").then((r) => r.categorias);
