import type { Metadata } from "next";
import { ListaNotificacoes } from "@/components/notificacoes";
import { TopoPainel } from "@/components/topo-painel";
import { listarNotificacoes } from "@/lib/notificacoes";

export const metadata: Metadata = { title: "Notificações" };

export default async function NotificacoesPainel() {
  const dados = await listarNotificacoes(100);
  return (
    <>
      <TopoPainel titulo="Notificações" />
      <main className="max-w-3xl p-4 sm:p-7">
        <ListaNotificacoes {...dados} />
      </main>
    </>
  );
}
