import { Plus, Search } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { excluir, importarIsbn, salvarCadastro, type Cadastro } from "@/app/painel/acervo/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { Paginacao } from "@/components/paginacao";
import { Campo, Escolha, Formulario } from "@/components/formulario";
import { TopoPainel } from "@/components/topo-painel";
import { estiloBotao } from "@/components/ui/button";
import { listarAutores, listarCategorias, listarEditoras } from "@/lib/acervo";
import { buscarCatalogo } from "@/lib/catalogo";
import { cn } from "@/lib/cn";

export const metadata: Metadata = { title: "Acervo" };

const abas = [
  { id: "livros", rotulo: "Livros" },
  { id: "autores", rotulo: "Autores" },
  { id: "editoras", rotulo: "Editoras" },
  { id: "categorias", rotulo: "Categorias" },
];

type Props = { searchParams: Promise<{ aba?: string; busca?: string; categoria?: string; situacao?: string; pagina?: string }> };

export default async function Acervo({ searchParams }: Props) {
  const { aba = "livros", busca = "", categoria = "", situacao = "", pagina } = await searchParams;
  const categorias = await listarCategorias();

  return (
    <>
      <TopoPainel titulo="Acervo" />
      <main className="flex flex-col gap-5 p-4 sm:p-7">
        <nav aria-label="Cadastros" className="flex w-fit flex-wrap gap-1 rounded-xl bg-zinc-100 p-1 dark:bg-zinc-900">
          {abas.map((a) => (
            <Link key={a.id} href={`/painel/acervo?aba=${a.id}`} aria-current={a.id === aba ? "page" : undefined}
              className={cn("rounded-lg px-3.5 py-2 text-sm font-medium", a.id === aba ? "bg-superficie shadow-sm" : "text-texto-suave hover:text-texto")}>
              {a.rotulo}
            </Link>
          ))}
        </nav>
        {aba === "livros" && <AbaLivros filtros={{ busca, categoria, situacao }} pagina={pagina} categorias={categorias} />}
        {aba === "autores" && <AbaCadastro tipo="autores" itens={(await listarAutores()).map((a) => ({ id: a.id, nome: a.nome, extra: a.nacionalidade, livros: a.livros }))} />}
        {aba === "editoras" && <AbaCadastro tipo="editoras" itens={(await listarEditoras()).map((e) => ({ id: e.id, nome: e.nome, extra: e.cidade, livros: e.livros }))} />}
        {aba === "categorias" && <AbaCadastro tipo="categorias" itens={categorias.map((c) => ({ id: c.id, nome: c.nome, extra: c.descricao, livros: c.livros }))} />}
      </main>
    </>
  );
}

const situacoes = [
  { valor: "disponivel", rotulo: "Com exemplar livre" },
  { valor: "indisponivel", rotulo: "Sem exemplar livre" },
  { valor: "fila", rotulo: "Com fila" },
];

const estiloFiltro = "h-11 rounded-xl border border-borda bg-superficie px-3 text-sm outline-none focus:border-marca";

type Filtros = { busca: string; categoria: string; situacao: string };

async function AbaLivros({ filtros, pagina, categorias }: { filtros: Filtros; pagina?: string; categorias: { id: number; nome: string }[] }) {
  const { busca, categoria, situacao } = filtros;
  const catalogo = await buscarCatalogo({ busca, categoria, situacao, pagina, porPagina: 25 });
  const { livros } = catalogo;
  return (
    <>
      <div className="flex flex-wrap items-end gap-4">
        <form className="flex flex-[1_1_520px] flex-wrap items-center gap-2">
          <input type="hidden" name="aba" value="livros" />
          <div className="flex h-11 flex-[1_1_220px] items-center gap-2 rounded-xl border border-borda bg-superficie px-3 focus-within:border-marca sm:max-w-sm">
            <Search className="size-4 text-texto-suave" aria-hidden />
            <label htmlFor="busca" className="sr-only">Buscar livro</label>
            <input id="busca" name="busca" type="search" defaultValue={busca} placeholder="Título, autor ou ISBN" className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-texto-suave" />
          </div>
          <label htmlFor="categoria" className="sr-only">Categoria</label>
          <select id="categoria" name="categoria" defaultValue={categoria} className={estiloFiltro}>
            <option value="">Todas as categorias</option>
            {categorias.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
          </select>
          <label htmlFor="situacao" className="sr-only">Situação</label>
          <select id="situacao" name="situacao" defaultValue={situacao} className={estiloFiltro}>
            <option value="">Qualquer situação</option>
            {situacoes.map((s) => <option key={s.valor} value={s.valor}>{s.rotulo}</option>)}
          </select>
          <button type="submit" className={estiloBotao({ variante: "contorno" })}>Filtrar</button>
          {(busca || categoria || situacao) && <Link href="/painel/acervo?aba=livros" className="text-sm text-texto-suave hover:text-texto">Limpar</Link>}
        </form>
        <Link href="/painel/acervo/livros/novo" className={estiloBotao({ variante: "contorno" })}><Plus className="size-4" aria-hidden />Novo livro</Link>
        <section aria-label="Importar por ISBN" className="ml-auto rounded-2xl border border-borda bg-superficie p-3">
          <Formulario acao={importarIsbn} rotulo="Importar da Open Library" pendente="Buscando…" linha>
            <Campo nome="isbn" rotulo="ISBN" placeholder="978-85-359-1066-7" className="w-48" />
            <Escolha nome="categoriaId" rotulo="Categoria" opcoes={categorias.map((c) => ({ valor: c.id, rotulo: c.nome }))} className="w-44" />
          </Formulario>
        </section>
      </div>
      <div className="overflow-x-auto rounded-2xl border border-borda bg-superficie">
        <table className="w-full text-sm">
          <thead className="text-left text-xs text-texto-suave">
            <tr>{["Título", "Autores", "Categoria", "Ano", "Livres", "Fila"].map((t) => <th key={t} className="px-4 py-3 font-medium">{t}</th>)}</tr>
          </thead>
          <tbody>
            {livros.map((l) => (
              <tr key={l.id} className="border-t border-borda hover:bg-fundo">
                <td className="px-4 py-3 font-medium"><Link href={`/painel/acervo/livros/${l.id}`} className="hover:text-marca">{l.titulo}</Link></td>
                <td className="px-4 py-3 text-texto-suave">{l.autores.join(", ") || "—"}</td>
                <td className="px-4 py-3">{l.categoria.nome}</td>
                <td className="px-4 py-3">{l.ano ?? "—"}</td>
                <td className="px-4 py-3">{l.disponiveis}</td>
                <td className="px-4 py-3">{l.fila}</td>
              </tr>
            ))}
            {livros.length === 0 && <tr><td colSpan={6} className="px-4 py-8 text-center text-texto-suave">Nenhum livro encontrado.</td></tr>}
          </tbody>
        </table>
      </div>
      <Paginacao {...catalogo} caminho="/painel/acervo" parametros={{ aba: "livros", busca, categoria, situacao }} />
    </>
  );
}

const rotulos: Record<Cadastro, { singular: string; extra: string }> = {
  autores: { singular: "autor", extra: "Nacionalidade" },
  editoras: { singular: "editora", extra: "Cidade" },
  categorias: { singular: "categoria", extra: "Descrição" },
};
const campoExtra: Record<Cadastro, string> = { autores: "nacionalidade", editoras: "cidade", categorias: "descricao" };

function AbaCadastro({ tipo, itens }: { tipo: Cadastro; itens: { id: number; nome: string; extra: string | null; livros: number }[] }) {
  const { singular, extra } = rotulos[tipo];
  return (
    <div className="flex flex-col gap-4">
      <section className="rounded-2xl border border-borda bg-superficie p-4">
        <Formulario acao={salvarCadastro.bind(null, tipo, null)} rotulo={`Adicionar ${singular}`} linha variante="primario">
          <Campo nome="nome" rotulo="Nome" className="flex-[1_1_220px]" />
          <Campo nome={campoExtra[tipo]} rotulo={extra} className="flex-[1_1_220px]" />
        </Formulario>
      </section>
      <ul className="divide-y divide-borda rounded-2xl border border-borda bg-superficie">
        {itens.map((item) => (
          <li key={item.id} className="flex flex-wrap items-end gap-3 px-4 py-3">
            <Formulario acao={salvarCadastro.bind(null, tipo, item.id)} rotulo="Salvar" linha className="flex-[1_1_480px]">
              <Campo nome="nome" rotulo="Nome" padrao={item.nome} className="flex-[1_1_200px]" />
              <Campo nome={campoExtra[tipo]} rotulo={extra} padrao={item.extra} className="flex-[1_1_200px]" />
            </Formulario>
            <span className="pb-3 text-xs text-texto-suave">{item.livros} livro(s)</span>
            <BotaoAcao acao={excluir.bind(null, `/api/${tipo}/${item.id}`, undefined)} rotulo="Excluir" pendente="Excluindo…" variante="fantasma" confirmar={`Excluir ${item.nome}?`} />
          </li>
        ))}
        {itens.length === 0 && <li className="px-4 py-8 text-center text-sm text-texto-suave">Nada cadastrado ainda.</li>}
      </ul>
    </div>
  );
}
