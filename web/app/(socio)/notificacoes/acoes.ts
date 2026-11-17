"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { api } from "@/lib/api";

export async function abrirNotificacao(id: number, link: string | null) {
  await api(`/api/notificacoes/${id}/leitura`, { method: "POST" }).catch(() => undefined);
  revalidatePath("/", "layout");
  if (link?.startsWith("/")) redirect(link);
}

export async function marcarTodasComoLidas() {
  await api("/api/notificacoes/leitura", { method: "POST" }).catch(() => undefined);
  revalidatePath("/", "layout");
}
