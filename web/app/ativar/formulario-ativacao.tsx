"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ativar, type EstadoAtivacao } from "./actions";

export function FormularioAtivacao() {
  const [estado, acao, enviando] = useActionState<EstadoAtivacao, FormData>(ativar, {});

  return (
    <form action={acao} className="flex flex-col gap-4" key={estado.erro}>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        E-mail cadastrado no balcão
        <Input name="email" type="email" autoComplete="email" defaultValue={estado.email} required />
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Código de ativação
        <Input
          name="codigo"
          autoComplete="one-time-code"
          placeholder="ABCD-2345"
          defaultValue={estado.codigo}
          className="font-mono uppercase tracking-widest"
          required
        />
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Crie uma senha
        <Input name="senha" type="password" autoComplete="new-password" minLength={8} required />
        <span className="text-xs font-normal text-texto-suave">Pelo menos 8 caracteres.</span>
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Repita a senha
        <Input name="confirmacao" type="password" autoComplete="new-password" minLength={8} required />
      </label>
      {estado.erro && (
        <p role="alert" className="rounded-xl border border-perigo/30 bg-perigo-suave px-3.5 py-2.5 text-sm text-perigo">
          {estado.erro}
        </p>
      )}
      <Button type="submit" tamanho="lg" disabled={enviando}>
        {enviando ? "Ativando…" : "Ativar e entrar"}
      </Button>
    </form>
  );
}
