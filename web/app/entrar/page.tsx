import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Marca } from "@/components/marca";
import { inicioDoPapel, usuarioAtual } from "@/lib/api";
import { FormularioLogin } from "./formulario-login";

export const metadata: Metadata = { title: "Entrar" };

export default async function PaginaEntrar() {
  const usuario = await usuarioAtual();
  if (usuario) redirect(inicioDoPapel(usuario.papel));

  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-12">
      <div className="flex w-full max-w-sm flex-col gap-8">
        <Marca />
        <div className="flex flex-col gap-1.5">
          <h1 className="text-3xl font-semibold tracking-tight">Entrar</h1>
          <p className="text-texto-suave">Sócios entram com o e-mail cadastrado no balcão.</p>
        </div>
        <div className="rounded-2xl border border-borda bg-superficie p-6 shadow-sm">
          <FormularioLogin />
        </div>
        <p className="text-center text-sm text-texto-suave">
          Primeiro acesso ou esqueceu a senha?{" "}
          <Link href="/ativar" className="font-medium text-marca hover:underline">Ative sua conta</Link>
        </p>
      </div>
    </main>
  );
}
