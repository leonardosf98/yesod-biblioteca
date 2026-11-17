"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { entrar, type EstadoLogin } from "./actions";

export function FormularioLogin() {
  const [estado, acao, enviando] = useActionState<EstadoLogin, FormData>(entrar, {});

  return (
    <form action={acao} className="flex flex-col gap-4">
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        E-mail ou login
        <Input name="login" autoComplete="username" defaultValue={estado.login} key={estado.login} required autoFocus={!estado.login} />
      </label>
      <label className="flex flex-col gap-1.5 text-sm font-medium">
        Senha
        <Input name="senha" type="password" autoComplete="current-password" required autoFocus={Boolean(estado.login)} />
      </label>
      {estado.erro && (
        <p role="alert" className="rounded-xl border border-perigo/30 bg-perigo-suave px-3.5 py-2.5 text-sm text-perigo">
          {estado.erro}
        </p>
      )}
      <Button type="submit" tamanho="lg" disabled={enviando}>
        {enviando ? "Entrando…" : "Entrar"}
      </Button>
    </form>
  );
}
