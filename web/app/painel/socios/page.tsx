import { Plus, Search } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { TopoPainel } from "@/components/topo-painel";
import { estiloBotao } from "@/components/ui/button";
import { buscarSocios } from "@/lib/painel";

export const metadata: Metadata = { title: "Sócios" };

export default async function Socios({ searchParams }: { searchParams: Promise<{ busca?: string }> }) {
  const { busca = "" } = await searchParams;
  const { socios, limite } = await buscarSocios(busca);

  return (
    <>
      <TopoPainel titulo="Sócios" />
      <main className="flex flex-col gap-5 p-4 sm:p-7">
        <div className="flex flex-wrap items-center gap-3">
          <form className="flex h-11 flex-[1_1_280px] items-center gap-2 rounded-xl border border-borda bg-superficie px-3 focus-within:border-marca sm:max-w-md">
            <Search className="size-4 text-texto-suave" aria-hidden />
            <label htmlFor="busca" className="sr-only">Buscar sócio</label>
            <input id="busca" name="busca" type="search" defaultValue={busca} placeholder="Nome ou e-mail" className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-texto-suave" />
          </form>
          <Link href="/painel/socios/novo" className={estiloBotao({ className: "ml-auto" })}><Plus className="size-4" aria-hidden />Novo sócio</Link>
        </div>
        <div className="overflow-x-auto rounded-2xl border border-borda bg-superficie">
          <table className="w-full text-sm">
            <thead className="text-left text-xs text-texto-suave">
              <tr>{["Nome", "E-mail", "Cidade", "Em uso", "Situação", "App"].map((t) => <th key={t} className="px-4 py-3 font-medium">{t}</th>)}</tr>
            </thead>
            <tbody>
              {socios.map((s) => (
                <tr key={s.id} className="border-t border-borda hover:bg-fundo">
                  <td className="px-4 py-3 font-medium"><Link href={`/painel/socios/${s.id}`} className="hover:text-marca">{s.nome}</Link></td>
                  <td className="px-4 py-3 text-texto-suave">{s.email}</td>
                  <td className="px-4 py-3 text-texto-suave">{s.cidade ?? "—"}</td>
                  <td className="px-4 py-3">{s.emUso} de {limite}</td>
                  <td className="px-4 py-3">{s.pendencias.length ? <span className="font-medium text-alerta">Pendência</span> : <span className="text-texto-suave">Em dia</span>}</td>
                  <td className="px-4 py-3 text-texto-suave">{s.contaAtiva ? "Ativa" : "—"}</td>
                </tr>
              ))}
              {socios.length === 0 && <tr><td colSpan={6} className="px-4 py-8 text-center text-texto-suave">Nenhum sócio encontrado.</td></tr>}
            </tbody>
          </table>
        </div>
      </main>
    </>
  );
}
