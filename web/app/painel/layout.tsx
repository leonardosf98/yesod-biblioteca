import { Barcode, BookMarked, Inbox, LayoutDashboard, Users } from "lucide-react";
import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { BotaoSair } from "@/components/botao-sair";
import { LinkNav } from "@/components/link-nav";
import { Marca } from "@/components/marca";
import { usuarioAtual } from "@/lib/api";

export const metadata: Metadata = { title: "Painel" };

const itens = [
  { href: "/painel", rotulo: "Painel", Icone: LayoutDashboard },
  { href: "/painel/balcao", rotulo: "Balcão", Icone: Barcode },
  { href: "/painel/pedidos", rotulo: "Pedidos", Icone: Inbox },
  { href: "/painel/socios", rotulo: "Sócios", Icone: Users },
  { href: "/painel/acervo", rotulo: "Acervo", Icone: BookMarked },
];

export default async function LayoutPainel({ children }: { children: React.ReactNode }) {
  const usuario = await usuarioAtual();
  if (!usuario) redirect("/entrar");
  if (usuario.papel !== "bibliotecario") redirect("/");

  return (
    <div className="flex min-h-dvh flex-wrap">
      <aside aria-label="Menu" className="flex flex-[1_1_232px] flex-col gap-6 bg-zinc-900 px-3.5 py-5 text-zinc-200 md:max-w-60">
        <Marca href="/painel" subtitulo="Balcão" className="px-2 text-white [&>span:first-child]:bg-teal-400 [&>span:first-child]:text-teal-950" />
        <nav aria-label="Principal" className="flex flex-col gap-0.5">
          {itens.map(({ href, rotulo, Icone }) => (
            <LinkNav key={href} href={href} escuro>
              <Icone className="size-4" aria-hidden />
              {rotulo}
            </LinkNav>
          ))}
        </nav>
        <div className="mt-auto flex items-center gap-2.5 rounded-xl bg-zinc-800 p-2.5">
          <span className="flex size-8 items-center justify-center rounded-full bg-zinc-700 text-xs font-semibold text-white">
            {usuario.login.slice(0, 2).toUpperCase()}
          </span>
          <span className="flex-1 text-sm">
            <strong className="block font-medium text-white">{usuario.login}</strong>
            <span className="text-zinc-400">Bibliotecário</span>
          </span>
          <BotaoSair className="size-9 text-zinc-300 hover:bg-zinc-700 hover:text-white" />
        </div>
      </aside>
      <div className="flex min-w-0 flex-[999_1_640px] flex-col">{children}</div>
    </div>
  );
}
