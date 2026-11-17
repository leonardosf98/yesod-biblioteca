import { Search } from "lucide-react";
import Link from "next/link";
import { Capa } from "@/components/capa";
import { SeloDisponibilidade } from "@/components/selo-disponibilidade";
import { cn } from "@/lib/cn";
import { buscarCatalogo } from "@/lib/catalogo";

type Props = { searchParams: Promise<{ busca?: string; categoria?: string }> };

export default async function Catalogo({ searchParams }: Props) {
  const { busca = "", categoria = "" } = await searchParams;
  const { livros, categorias } = await buscarCatalogo({ busca, categoria });

  const linkCategoria = (id?: number) => {
    const parametros = new URLSearchParams();
    if (busca) parametros.set("busca", busca);
    if (id) parametros.set("categoria", String(id));
    return parametros.size ? `/?${parametros}` : "/";
  };

  return (
    <div className="flex flex-col gap-7">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex flex-col gap-1.5">
          <h1 className="text-3xl font-semibold tracking-tight">Catálogo</h1>
          <p className="text-texto-suave">Escolha um livro e peça pelo app. Você retira no balcão em até 48 h.</p>
        </div>
        <form role="search" className="flex h-11 w-full max-w-sm items-center gap-2 rounded-xl border border-borda bg-superficie px-3 focus-within:border-marca">
          <Search className="size-4 text-texto-suave" aria-hidden />
          <label htmlFor="busca" className="sr-only">Buscar no acervo</label>
          <input id="busca" name="busca" type="search" defaultValue={busca} placeholder="Título, autor ou ISBN" className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-texto-suave" />
          {categoria && <input type="hidden" name="categoria" value={categoria} />}
        </form>
      </div>

      <nav aria-label="Categorias" className="flex flex-wrap gap-2">
        {[{ id: 0, nome: "Todas" }, ...categorias].map((c) => {
          const ativa = c.id === 0 ? !categoria : String(c.id) === categoria;
          return (
            <Link
              key={c.id}
              href={linkCategoria(c.id || undefined)}
              aria-current={ativa ? "page" : undefined}
              className={cn(
                "flex h-9 items-center rounded-full border px-3.5 text-sm font-medium transition-colors",
                ativa ? "border-texto bg-texto text-fundo" : "border-borda bg-superficie text-texto-suave hover:text-texto",
              )}
            >
              {c.nome}
            </Link>
          );
        })}
      </nav>

      {livros.length === 0 ? (
        <p className="rounded-2xl border border-dashed border-borda px-6 py-14 text-center text-texto-suave">
          Nenhum livro encontrado{busca && <> para “{busca}”</>}.
        </p>
      ) : (
        <ul className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-x-6 gap-y-8 sm:grid-cols-[repeat(auto-fill,minmax(176px,1fr))]">
          {livros.map((livro) => (
            <li key={livro.id}>
              <Link href={`/livros/${livro.id}`} className="group flex flex-col gap-2.5">
                <Capa {...livro} className="transition-transform group-hover:-translate-y-0.5" />
                <span className="flex flex-col gap-1">
                  <span className="font-semibold leading-snug">{livro.titulo}</span>
                  <span className="text-sm text-texto-suave">{livro.autores.join(", ")}</span>
                  <SeloDisponibilidade disponiveis={livro.disponiveis} fila={livro.fila} className="mt-1" />
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
