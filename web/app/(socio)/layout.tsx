import Link from "next/link";
import { BotaoSair } from "@/components/botao-sair";
import { LinkNav } from "@/components/link-nav";
import { Marca } from "@/components/marca";
import { Sino } from "@/components/notificacoes";
import { estiloBotao } from "@/components/ui/button";
import { usuarioAtual } from "@/lib/api";
import { listarNotificacoes } from "@/lib/notificacoes";

export default async function LayoutSocio({ children }: { children: React.ReactNode }) {
  const usuario = await usuarioAtual();
  const avisos = usuario ? await listarNotificacoes(8) : null;

  return (
    <>
      <header className="border-b border-borda bg-superficie">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-7 gap-y-3 px-4 py-3 sm:px-6">
          <Marca />
          <nav aria-label="Principal" className="flex flex-wrap gap-1">
            <LinkNav href="/">Catálogo</LinkNav>
            {usuario?.papel === "socio" && <LinkNav href="/emprestimos">Meus empréstimos</LinkNav>}
            {usuario?.papel === "bibliotecario" && <LinkNav href="/painel">Painel</LinkNav>}
          </nav>
          <div className="ml-auto flex items-center gap-2">
            {usuario ? (
              <>
                {avisos && <Sino {...avisos} verTodas={usuario.papel === "bibliotecario" ? "/painel/notificacoes" : "/notificacoes"} />}
                <span className="flex size-11 items-center justify-center rounded-full bg-marca-suave text-sm font-semibold text-marca-forte" title={usuario.login}>
                  {usuario.login.slice(0, 2).toUpperCase()}
                </span>
                <BotaoSair className="border border-borda text-texto-suave hover:text-texto" />
              </>
            ) : (
              <Link href="/entrar" className={estiloBotao({ variante: "contorno" })}>
                Entrar
              </Link>
            )}
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 pb-14 pt-7 sm:px-6">{children}</main>
    </>
  );
}
