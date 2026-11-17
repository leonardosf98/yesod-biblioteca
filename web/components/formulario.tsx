"use client";

import { createContext, useActionState, useContext } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/cn";

type Estado = { erro?: string; ok?: string; campos?: Record<string, string>; valores?: Record<string, string> };
const Contexto = createContext<Estado>({});

export function Formulario({ acao, rotulo, pendente = "Salvando…", children, className, variante, linha }: {
  acao: (anterior: Estado, dados: FormData) => Promise<Estado>;
  rotulo: string;
  pendente?: string;
  children: React.ReactNode;
  className?: string;
  variante?: "primario" | "contorno";
  linha?: boolean;
}) {
  const [estado, executar, enviando] = useActionState(acao, {});
  if (linha) {
    return (
      <form action={executar} className={cn("flex flex-wrap items-start gap-2", className)}>
        <Contexto.Provider value={estado}>
          <div key={JSON.stringify(estado.valores ?? {})} className="contents">{children}</div>
        </Contexto.Provider>
        <Button type="submit" variante={variante ?? "contorno"} disabled={enviando}>{enviando ? pendente : rotulo}</Button>
        {estado.erro && Object.keys(estado.campos ?? {}).length === 0 && <p role="alert" className="w-full text-sm text-perigo">{estado.erro}</p>}
        {estado.ok && <p role="status" className="w-full text-xs text-marca-forte">{estado.ok}</p>}
      </form>
    );
  }
  return (
    <form action={executar} className={cn("flex flex-col gap-4", className)}>
      <Contexto.Provider value={estado}>
        <div key={JSON.stringify(estado.valores ?? {})} className="contents">{children}</div>
      </Contexto.Provider>
      {estado.erro && <p role="alert" className="rounded-xl border border-perigo/30 bg-perigo-suave px-3.5 py-2.5 text-sm text-perigo">{estado.erro}</p>}
      {estado.ok && <p role="status" className="text-sm text-marca-forte">{estado.ok}</p>}
      <Button type="submit" variante={variante} disabled={enviando} className="w-fit">{enviando ? pendente : rotulo}</Button>
    </form>
  );
}

export function Campo({ nome, rotulo, padrao, className, ...props }: Omit<React.ComponentProps<"input">, "name" | "defaultValue"> & {
  nome: string;
  rotulo: string;
  padrao?: string | number | null;
}) {
  const { campos, valores } = useContext(Contexto);
  const erro = campos?.[nome];
  return (
    <label className={cn("flex flex-col gap-1.5 text-sm font-medium", className)}>
      {rotulo}
      <Input name={nome} defaultValue={valores?.[nome] ?? padrao ?? ""} aria-invalid={Boolean(erro)} className={cn(erro && "border-perigo")} {...props} />
      {erro && <span className="text-xs font-normal text-perigo">{erro}</span>}
    </label>
  );
}

export function Escolha({ nome, rotulo, padrao, opcoes, multipla, className }: {
  nome: string;
  rotulo: string;
  padrao?: string | number | (string | number)[] | null;
  opcoes: { valor: string | number; rotulo: string }[];
  multipla?: boolean;
  className?: string;
}) {
  const { campos, valores } = useContext(Contexto);
  const erro = campos?.[nome];
  const inicial = valores?.[nome] ?? (Array.isArray(padrao) ? padrao.map(String) : padrao == null ? "" : String(padrao));
  return (
    <label className={cn("flex flex-col gap-1.5 text-sm font-medium", className)}>
      {rotulo}
      <select
        name={nome}
        multiple={multipla}
        defaultValue={inicial}
        className={cn("min-h-11 rounded-xl border border-borda bg-superficie px-3 text-[15px] outline-none focus:border-marca", multipla && "py-2", erro && "border-perigo")}
      >
        {!multipla && <option value="">—</option>}
        {opcoes.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}
      </select>
      {erro && <span className="text-xs font-normal text-perigo">{erro}</span>}
    </label>
  );
}

export function AreaTexto({ nome, rotulo, padrao, className }: { nome: string; rotulo: string; padrao?: string | null; className?: string }) {
  const { campos, valores } = useContext(Contexto);
  const erro = campos?.[nome];
  return (
    <label className={cn("flex flex-col gap-1.5 text-sm font-medium", className)}>
      {rotulo}
      <textarea
        name={nome}
        rows={4}
        defaultValue={valores?.[nome] ?? padrao ?? ""}
        className={cn("rounded-xl border border-borda bg-superficie px-3.5 py-2.5 text-[15px] font-normal outline-none focus:border-marca", erro && "border-perigo")}
      />
      {erro && <span className="text-xs font-normal text-perigo">{erro}</span>}
    </label>
  );
}
