import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/cn";

type Props = {
  pagina: number;
  paginas: number;
  total: number;
  porPagina: number;
  caminho: string;
  parametros: Record<string, string | undefined>;
};

export function Paginacao({ pagina, paginas, total, porPagina, caminho, parametros }: Props) {
  if (paginas <= 1) return null;

  const link = (p: number) => {
    const consulta = new URLSearchParams();
    for (const [chave, valor] of Object.entries(parametros)) if (valor) consulta.set(chave, valor);
    if (p > 1) consulta.set("pagina", String(p));
    return consulta.size ? `${caminho}?${consulta}` : caminho;
  };

  const inicio = (pagina - 1) * porPagina + 1;
  const fim = Math.min(pagina * porPagina, total);
  const numeros = Array.from({ length: paginas }, (_, i) => i + 1)
    .filter((p) => p === 1 || p === paginas || Math.abs(p - pagina) <= 1);

  const seta = "flex size-9 items-center justify-center rounded-lg border border-borda bg-superficie";
  return (
    <nav aria-label="Paginação" className="flex flex-wrap items-center justify-between gap-3">
      <p className="text-sm text-texto-suave">{inicio}–{fim} de {total}</p>
      <div className="flex items-center gap-1">
        {pagina > 1
          ? <Link href={link(pagina - 1)} className={cn(seta, "hover:text-marca")} aria-label="Página anterior"><ChevronLeft className="size-4" /></Link>
          : <span className={cn(seta, "opacity-40")} aria-hidden><ChevronLeft className="size-4" /></span>}
        {numeros.map((p, i) => (
          <span key={p} className="flex items-center gap-1">
            {i > 0 && p - numeros[i - 1] > 1 && <span className="px-1 text-texto-suave" aria-hidden>…</span>}
            <Link
              href={link(p)}
              aria-current={p === pagina ? "page" : undefined}
              className={cn(
                "flex h-9 min-w-9 items-center justify-center rounded-lg border px-2 text-sm font-medium",
                p === pagina ? "border-texto bg-texto text-fundo" : "border-borda bg-superficie text-texto-suave hover:text-texto",
              )}
            >
              {p}
            </Link>
          </span>
        ))}
        {pagina < paginas
          ? <Link href={link(pagina + 1)} className={cn(seta, "hover:text-marca")} aria-label="Próxima página"><ChevronRight className="size-4" /></Link>
          : <span className={cn(seta, "opacity-40")} aria-hidden><ChevronRight className="size-4" /></span>}
      </div>
    </nav>
  );
}
