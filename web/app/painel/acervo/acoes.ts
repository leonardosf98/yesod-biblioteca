"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { ResultadoAcao } from "@/components/botao-acao";
import { api, ErroApi } from "@/lib/api";
import { enviar, texto, type EstadoForm } from "@/lib/formulario";

export type Cadastro = "autores" | "editoras" | "categorias";
const segundoCampo: Record<Cadastro, string> = { autores: "nacionalidade", editoras: "cidade", categorias: "descricao" };

function inteiro(dados: FormData, nome: string) {
  const valor = texto(dados, nome);
  return valor === null ? null : Number(valor);
}

export async function salvarCadastro(tipo: Cadastro, id: number | null, _: EstadoForm, dados: FormData) {
  const corpo = { nome: texto(dados, "nome"), [segundoCampo[tipo]]: texto(dados, segundoCampo[tipo]) };
  return id === null
    ? enviar(`/api/${tipo}`, "POST", dados, corpo, { revalidar: "/painel/acervo", ok: "Cadastrado." })
    : enviar(`/api/${tipo}/${id}`, "PUT", dados, corpo, { revalidar: "/painel/acervo", ok: "Salvo." });
}

export async function excluir(caminho: string, destino?: string): Promise<ResultadoAcao> {
  try {
    await api(caminho, { method: "DELETE" });
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível excluir." };
  }
  revalidatePath("/painel/acervo", "layout");
  if (destino) redirect(destino);
  return { ok: "Excluído." };
}

function corpoLivro(dados: FormData) {
  return {
    titulo: texto(dados, "titulo"),
    isbn: texto(dados, "isbn"),
    ano: inteiro(dados, "ano"),
    sinopse: texto(dados, "sinopse"),
    capaUrl: texto(dados, "capaUrl"),
    editoraId: inteiro(dados, "editoraId"),
    categoriaId: inteiro(dados, "categoriaId"),
    autores: dados.getAll("autores").map(Number),
  };
}

export async function salvarLivro(id: number | null, _: EstadoForm, dados: FormData) {
  return id === null
    ? enviar("/api/livros", "POST", dados, corpoLivro(dados), { revalidar: "/", destino: (r) => `/painel/acervo/livros/${r.id}` })
    : enviar(`/api/livros/${id}`, "PUT", dados, corpoLivro(dados), { revalidar: "/", ok: "Livro salvo." });
}

export async function importarIsbn(_: EstadoForm, dados: FormData) {
  return enviar("/api/livros/importacao", "POST", dados, { isbn: texto(dados, "isbn"), categoriaId: inteiro(dados, "categoriaId") }, {
    revalidar: "/",
    destino: (r) => `/painel/acervo/livros/${r.id}`,
  });
}

export async function salvarExemplar(livroId: number, id: number | null, _: EstadoForm, dados: FormData) {
  const corpo = { codigo: texto(dados, "codigo"), estado: texto(dados, "estado") };
  return id === null
    ? enviar(`/api/livros/${livroId}/exemplares`, "POST", dados, corpo, { revalidar: "/", ok: "Exemplar cadastrado." })
    : enviar(`/api/exemplares/${id}`, "PUT", dados, corpo, { revalidar: "/", ok: "Salvo." });
}
