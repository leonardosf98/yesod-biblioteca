import { AlertTriangle, Clock, RefreshCw } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { entrarNaFila, pedir } from "@/app/(socio)/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { Capa } from "@/components/capa";
import { SeloDisponibilidade } from "@/components/selo-disponibilidade";
import { estiloBotao } from "@/components/ui/button";
import { ErroApi, usuarioAtual } from "@/lib/api";
import { buscarLivro, type LivroDetalhe } from "@/lib/catalogo";
import { buscarMeusEmprestimos } from "@/lib/emprestimos";
import { dataHora } from "@/lib/formato";

type Props = { params: Promise<{ id: string }> };

async function carregar(id: string) {
  try {
    return await buscarLivro(id);
  } catch (erro) {
    if (erro instanceof ErroApi && erro.status === 404) notFound();
    throw erro;
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  return { title: (await carregar((await params).id)).titulo };
}

export default async function PaginaLivro({ params }: Props) {
  const livro = await carregar((await params).id);
  const autores = livro.autores.map((a) => a.nome);

  return (
    <div className="flex flex-col gap-6">
      <nav aria-label="Trilha" className="flex gap-2 text-sm text-texto-suave">
        <Link href="/" className="hover:text-texto">Catálogo</Link>
        <span aria-hidden>/</span>
        <Link href={`/?categoria=${livro.categoria.id}`} className="hover:text-texto">{livro.categoria.nome}</Link>
      </nav>
      <div className="flex flex-wrap items-start gap-10">
        <div className="w-full max-w-[280px] flex-[0_1_280px]">
          <Capa id={livro.id} titulo={livro.titulo} autores={autores} capaUrl={livro.capaUrl} />
        </div>
        <div className="flex min-w-0 flex-[999_1_420px] flex-col gap-5">
          <div className="flex flex-col gap-2">
            <span className="w-fit rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-texto-suave dark:bg-zinc-800">{livro.categoria.nome}</span>
            <h1 className="text-4xl font-semibold tracking-tight">{livro.titulo}</h1>
            <p className="text-lg text-texto-suave">{autores.join(", ")}</p>
          </div>
          <dl className="grid grid-cols-2 gap-4 border-y border-borda py-4 sm:grid-cols-3">
            {[["Editora", livro.editora], ["Ano", livro.ano], ["ISBN", livro.isbn]].map(([rotulo, valor]) => (
              <div key={String(rotulo)}>
                <dt className="text-xs text-texto-suave">{rotulo}</dt>
                <dd className="mt-1 text-sm font-medium">{valor ?? "—"}</dd>
              </div>
            ))}
          </dl>
          {livro.sinopse && <p className="max-w-2xl leading-relaxed text-texto-suave">{livro.sinopse}</p>}
          {livro.exemplares.length > 0 && (
            <section className="flex flex-col gap-2.5">
              <h2 className="font-semibold">Exemplares</h2>
              <ul className="divide-y divide-borda overflow-hidden rounded-xl border border-borda bg-superficie text-sm">
                {livro.exemplares.map((e) => (
                  <li key={e.codigo} className="flex items-center justify-between gap-4 px-4 py-3">
                    <span className="font-mono">{e.codigo}</span>
                    <span className="text-texto-suave">{e.estado === "bom" ? "Bom" : "Danificado"}</span>
                    <span className={e.disponivel ? "font-medium text-marca-forte" : "text-texto-suave"}>{e.disponivel ? "Na estante" : "Indisponível"}</span>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>
        <PainelPedido livro={livro} />
      </div>
    </div>
  );
}

async function PainelPedido({ livro }: { livro: LivroDetalhe }) {
  const usuario = await usuarioAtual();
  const conta = usuario?.papel === "socio" ? await buscarMeusEmprestimos() : null;
  const pedido = conta?.pedidos.find((p) => p.livro.id === livro.id);
  const comigo = conta?.emprestimos.some((e) => e.livro.id === livro.id && !e.dataDevolucao);
  const naFila = conta?.reservas.find((r) => r.livro.id === livro.id);

  return (
    <aside aria-label="Pedir empréstimo" className="flex w-full flex-[1_1_300px] flex-col gap-4 rounded-2xl border border-borda bg-superficie p-6 shadow-sm md:max-w-[360px]">
      <SeloDisponibilidade disponiveis={livro.disponiveis} fila={livro.fila} />
      {!usuario && (
        <Link href="/entrar" className={estiloBotao({ tamanho: "lg" })}>Entre para pedir</Link>
      )}
      {usuario?.papel === "bibliotecario" && <p className="text-sm text-texto-suave">Pedidos são feitos pelos sócios. O balcão fica no painel.</p>}
      {conta && pedido && (
        <div className="flex flex-col items-center gap-1 rounded-xl border border-dashed border-marca-borda bg-marca-suave p-4 text-center">
          <span className="text-xs text-marca-forte">Retire até {dataHora(pedido.limiteRetirada)} com o código</span>
          <span className="font-mono text-2xl font-semibold tracking-widest text-marca-forte">{pedido.codigo}</span>
        </div>
      )}
      {conta && !pedido && comigo && <p className="text-sm text-texto-suave">Esse livro está com você. Veja o prazo em <Link href="/emprestimos" className="font-medium text-marca">Meus empréstimos</Link>.</p>}
      {conta && !pedido && !comigo && naFila && <p className="text-sm text-texto-suave">Você é o {naFila.posicao}º da fila. Avisamos quando um exemplar voltar.</p>}
      {conta && !pedido && !comigo && !naFila && (
        <>
          {conta.pendencias.map((p) => (
            <p key={p} className="flex gap-2 rounded-xl border border-perigo/30 bg-perigo-suave p-3 text-sm text-perigo">
              <AlertTriangle className="size-5 flex-none" aria-hidden />
              {p}
            </p>
          ))}
          {livro.disponiveis > 0 ? (
            <>
              <ul className="flex flex-col gap-2.5 text-sm text-texto-suave">
                <li className="flex gap-2.5"><Clock className="size-[18px] text-marca" aria-hidden />Retire no balcão em até 48 h</li>
                <li className="flex gap-2.5"><RefreshCw className="size-[18px] text-marca" aria-hidden />14 dias de prazo, renovável uma vez por mais 7</li>
              </ul>
              <BotaoAcao acao={pedir.bind(null, livro.id)} rotulo="Pedir empréstimo" pendente="Separando…" tamanho="lg" />
            </>
          ) : (
            <BotaoAcao acao={entrarNaFila.bind(null, livro.id)} rotulo="Entrar na fila" pendente="Entrando…" tamanho="lg" variante="contorno" />
          )}
        </>
      )}
      {conta && (
        <div className="flex justify-between border-t border-borda pt-3.5 text-sm">
          <span className="text-texto-suave">Seus empréstimos</span>
          <strong className="font-semibold">{conta.emUso} de {conta.limite}</strong>
        </div>
      )}
    </aside>
  );
}
