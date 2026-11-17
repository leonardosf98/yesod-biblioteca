import type { Metadata } from "next";
import { salvarLivro } from "@/app/painel/acervo/acoes";
import { CamposLivro } from "@/components/campos-livro";
import { Formulario } from "@/components/formulario";
import { TopoPainel } from "@/components/topo-painel";

export const metadata: Metadata = { title: "Novo livro" };

export default function NovoLivro() {
  return (
    <>
      <TopoPainel titulo="Novo livro" />
      <main className="p-4 sm:p-7">
        <section className="max-w-3xl rounded-2xl border border-borda bg-superficie p-6">
          <Formulario acao={salvarLivro.bind(null, null)} rotulo="Cadastrar livro"><CamposLivro /></Formulario>
        </section>
      </main>
    </>
  );
}
