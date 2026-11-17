"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/cn";

export function LinkNav({ href, children, escuro = false }: { href: string; children: React.ReactNode; escuro?: boolean }) {
  const caminho = usePathname();
  const ativo = href === "/" || href === "/painel" ? caminho === href : caminho.startsWith(href);
  return (
    <Link
      href={href}
      aria-current={ativo ? "page" : undefined}
      className={cn(
        "flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        escuro
          ? ativo ? "bg-zinc-800 text-white" : "text-zinc-300 hover:bg-zinc-800/60 hover:text-white"
          : ativo ? "bg-zinc-100 text-texto dark:bg-zinc-800" : "text-texto-suave hover:text-texto",
      )}
    >
      {children}
    </Link>
  );
}
