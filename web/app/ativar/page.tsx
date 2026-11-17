import type { Metadata } from "next";
import Link from "next/link";
import { Marca } from "@/components/marca";
import { FormularioAtivacao } from "./formulario-ativacao";

export const metadata: Metadata = { title: "Ativar conta" };

export default function PaginaAtivar() {
  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-12">
      <div className="flex w-full max-w-sm flex-col gap-8">
        <Marca />
        <div className="flex flex-col gap-1.5">
          <h1 className="text-3xl font-semibold tracking-tight">Ativar conta</h1>
          <p className="text-texto-suave">Use o código que a biblioteca te entregou. Serve também para trocar uma senha esquecida.</p>
        </div>
        <div className="rounded-2xl border border-borda bg-superficie p-6 shadow-sm">
          <FormularioAtivacao />
        </div>
        <p className="text-center text-sm text-texto-suave">
          Já tem senha? <Link href="/entrar" className="font-medium text-marca hover:underline">Entrar</Link>
        </p>
      </div>
    </main>
  );
}
