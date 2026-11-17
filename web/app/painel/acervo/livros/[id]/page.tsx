import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { excluir, salvarExemplar, salvarLivro } from "@/app/painel/acervo/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { CamposLivro } from "@/components/campos-livro";
import { Capa } from "@/components/capa";
import { Campo, Escolha, Formulario } from "@/components/formulario";
import { TopoPainel } from "@/components/topo-painel";
import { ErroApi } from "@/lib/api";
import { buscarLivro } from "@/lib/catalogo";

export const metadata: Metadata = { title: "Livro" };

const estados = [
  { valor: "bom", rotulo: "Bom" },
  { valor: "danificado", rotulo: "Danificado" },
  { valor: "perdido", rotulo: "Perdido" },
];

export default async function EditarLivro({ params }: { params: Promise<{ id: string }> }) {
  const livro = await buscarLivro((await params).id).catch((erro) => {
    if (erro instanceof ErroApi && erro.status === 404) notFound();
    throw erro;
  });

  return (
    <>
      <TopoPainel titulo={livro.titulo} />
      <main className="flex flex-wrap items-start gap-6 p-4 sm:p-7">
        <section className="min-w-0 flex-[3_1_520px] rounded-2xl border border-borda bg-superficie p-6">
          <Formulario acao={salvarLivro.bind(null, livro.id)} rotulo="Salvar livro"><CamposLivro livro={livro} /></Formulario>
        </section>
        <aside className="flex w-full flex-[1_1_300px] flex-col gap-4 md:max-w-sm">
          <div className="w-40"><Capa id={livro.id} titulo={livro.titulo} autores={livro.autores.map((a) => a.nome)} capaUrl={livro.capaUrl} /></div>
          <Link href={`/livros/${livro.id}`} className="text-sm font-medium text-marca hover:underline">Ver como o sócio vê</Link>
          <section className="flex flex-col gap-3 rounded-2xl border border-borda bg-superficie p-4">
            <h2 className="font-semibold">Exemplares</h2>
            {livro.exemplares.map((e) => (
              <div key={e.id} className="flex flex-col gap-1 border-t border-borda pt-3">
                <Formulario acao={salvarExemplar.bind(null, livro.id, e.id)} rotulo="Salvar" linha>
                  <Campo nome="codigo" rotulo="Código" padrao={e.codigo} className="w-28 font-mono" />
                  <Escolha nome="estado" rotulo="Estado" padrao={e.estado} opcoes={estados} className="w-32" />
                </Formulario>
                <span className="text-xs text-texto-suave">{e.disponivel ? "Na estante" : "Emprestado ou separado"}</span>
                <BotaoAcao acao={excluir.bind(null, `/api/exemplares/${e.id}`, undefined)} rotulo="Excluir exemplar" pendente="Excluindo…" variante="fantasma" className="w-fit" confirmar={`Excluir o exemplar ${e.codigo}?`} />
              </div>
            ))}
            <div className="border-t border-borda pt-3">
              <Formulario acao={salvarExemplar.bind(null, livro.id, null)} rotulo="Adicionar" linha variante="primario">
                <Campo nome="codigo" rotulo="Código (vazio gera)" className="w-36 font-mono" />
                <Escolha nome="estado" rotulo="Estado" padrao="bom" opcoes={estados} className="w-32" />
              </Formulario>
            </div>
          </section>
          <BotaoAcao acao={excluir.bind(null, `/api/livros/${livro.id}`, "/painel/acervo")} rotulo="Excluir livro" pendente="Excluindo…" variante="fantasma" className="w-fit" confirmar={`Excluir ${livro.titulo}?`} />
        </aside>
      </main>
    </>
  );
}
