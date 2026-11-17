"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/cn";

export type ResultadoAcao = { erro?: string; ok?: string };

export function BotaoAcao({ acao, rotulo, pendente, variante, tamanho, className }: {
  acao: (anterior: ResultadoAcao) => Promise<ResultadoAcao>;
  rotulo: React.ReactNode;
  pendente: string;
  variante?: "primario" | "contorno" | "fantasma";
  tamanho?: "md" | "lg";
  className?: string;
}) {
  const [estado, executar, enviando] = useActionState(acao, {});
  return (
    <form action={executar} className={cn("flex flex-col gap-2", className)}>
      <Button type="submit" variante={variante} tamanho={tamanho} disabled={enviando}>
        {enviando ? pendente : rotulo}
      </Button>
      {estado.erro && <p role="alert" className="text-sm text-perigo">{estado.erro}</p>}
      {estado.ok && <p role="status" className="text-sm text-marca-forte">{estado.ok}</p>}
    </form>
  );
}
