import { Plus, Search } from "lucide-react";
import Link from "next/link";
import { Sino } from "@/components/notificacoes";
import { estiloBotao } from "@/components/ui/button";
import { listarNotificacoes } from "@/lib/notificacoes";

export async function TopoPainel({ titulo }: { titulo: string }) {
  const avisos = await listarNotificacoes(8);
  return (
    <header className="flex flex-wrap items-center gap-3 border-b border-borda bg-superficie px-7 py-3.5">
      <h1 className="mr-auto text-lg font-semibold">{titulo}</h1>
      <form action="/painel/balcao" className="flex h-10 w-full max-w-sm items-center gap-2 rounded-xl border border-borda bg-fundo px-3 focus-within:border-marca sm:w-auto sm:flex-[0_1_360px]">
        <Search className="size-4 text-texto-suave" aria-hidden />
        <label htmlFor="codigo-topo" className="sr-only">Código do exemplar</label>
        <input id="codigo-topo" name="devolver" placeholder="Código do exemplar" className="min-w-0 flex-1 bg-transparent font-mono text-sm uppercase outline-none placeholder:font-sans placeholder:normal-case placeholder:text-texto-suave" />
      </form>
      <Link href="/painel/balcao" className={estiloBotao({ className: "h-10" })}>
        <Plus className="size-4" aria-hidden />Novo empréstimo
      </Link>
      <Sino {...avisos} verTodas="/painel/notificacoes" />
    </header>
  );
}
