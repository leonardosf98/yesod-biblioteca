import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { ListaNotificacoes } from "@/components/notificacoes";
import { usuarioAtual } from "@/lib/api";
import { listarNotificacoes } from "@/lib/notificacoes";

export const metadata: Metadata = { title: "Notificações" };

export default async function PaginaNotificacoes() {
  if (!(await usuarioAtual())) redirect("/entrar");
  const dados = await listarNotificacoes(100);
  return (
    <div className="flex max-w-2xl flex-col gap-6">
      <h1 className="text-3xl font-semibold tracking-tight">Notificações</h1>
      <ListaNotificacoes {...dados} />
    </div>
  );
}
