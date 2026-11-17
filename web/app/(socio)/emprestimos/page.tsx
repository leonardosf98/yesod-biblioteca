import { AlertTriangle, RefreshCw } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { cancelarPedido, renovar, sairDaFila } from "@/app/(socio)/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { Capa } from "@/components/capa";
import { usuarioAtual } from "@/lib/api";
import { cn } from "@/lib/cn";
import { buscarMeusEmprestimos, type Emprestimo } from "@/lib/emprestimos";
import { dataCurta, dataHora, diasEntre, hojeIso, reais } from "@/lib/formato";

export const metadata: Metadata = { title: "Meus empréstimos" };

type Props = { searchParams: Promise<{ aba?: string }> };

export default async function MeusEmprestimos({ searchParams }: Props) {
  const usuario = await usuarioAtual();
  if (!usuario) redirect("/entrar");
  if (usuario.papel !== "socio") redirect("/painel");

  const { aba = "andamento" } = await searchParams;
  const conta = await buscarMeusEmprestimos();
  const abertos = conta.emprestimos.filter((e) => !e.dataDevolucao);
  const historico = conta.emprestimos.filter((e) => e.dataDevolucao);
  const abas = [
    { id: "andamento", rotulo: `Em andamento (${abertos.length})` },
    { id: "pedidos", rotulo: `Pedidos e fila (${conta.pedidos.length + conta.reservas.length})` },
    { id: "historico", rotulo: "Histórico" },
  ];
  const multaAberta = historico.filter((e) => e.multaCentavos > 0 && !e.multaPaga).reduce((t, e) => t + e.multaCentavos, 0);

  return (
    <div className="flex flex-wrap items-start gap-8">
      <div className="flex min-w-0 flex-[999_1_560px] flex-col gap-5">
        <h1 className="text-3xl font-semibold tracking-tight">Meus empréstimos</h1>
        {conta.pendencias.map((p) => (
          <p key={p} role="alert" className="flex gap-3 rounded-xl border border-perigo/30 bg-perigo-suave p-3.5 text-sm text-perigo">
            <AlertTriangle className="size-5 flex-none" aria-hidden />
            {p}
          </p>
        ))}
        <nav aria-label="Situação" className="flex w-fit flex-wrap gap-1 rounded-xl bg-zinc-100 p-1 dark:bg-zinc-900">
          {abas.map((a) => (
            <Link
              key={a.id}
              href={`/emprestimos?aba=${a.id}`}
              aria-current={a.id === aba ? "page" : undefined}
              className={cn("rounded-lg px-3.5 py-2 text-sm font-medium", a.id === aba ? "bg-superficie shadow-sm" : "text-texto-suave hover:text-texto")}
            >
              {a.rotulo}
            </Link>
          ))}
        </nav>

        {aba === "andamento" && (
          abertos.length === 0
            ? <Vazio>Nenhum livro com você agora. <Link href="/" className="font-medium text-marca">Ver o catálogo</Link></Vazio>
            : abertos.map((e) => <CartaoEmprestimo key={e.id} emprestimo={e} bloqueado={conta.pendencias.length > 0} />)
        )}

        {aba === "pedidos" && (
          conta.pedidos.length + conta.reservas.length === 0 ? <Vazio>Nenhum pedido ou reserva.</Vazio> : (
            <>
              {conta.pedidos.map((p) => (
                <article key={p.id} className="flex flex-wrap items-center gap-5 rounded-2xl border border-marca-borda bg-superficie p-4.5">
                  <Capa id={p.livro.id} titulo={p.livro.titulo} autores={[]} capaUrl={p.livro.capaUrl} className="w-[72px] flex-none rounded-lg [&_span]:hidden" />
                  <div className="flex flex-[1_1_220px] flex-col gap-1">
                    <span className="w-fit rounded-full bg-marca-suave px-2.5 py-0.5 text-xs font-semibold text-marca-forte">Aguardando retirada</span>
                    <h2 className="font-semibold">{p.livro.titulo}</h2>
                    <p className="text-sm text-texto-suave">Retire até {dataHora(p.limiteRetirada)}</p>
                  </div>
                  <div className="flex flex-col items-center rounded-xl border border-dashed border-marca-borda bg-marca-suave px-5 py-3">
                    <span className="text-xs text-marca-forte">Código</span>
                    <span className="font-mono text-2xl font-semibold tracking-widest text-marca-forte">{p.codigo}</span>
                  </div>
                  <BotaoAcao acao={cancelarPedido.bind(null, p.id)} rotulo="Cancelar" pendente="Cancelando…" variante="contorno" />
                </article>
              ))}
              {conta.reservas.map((r) => (
                <article key={r.id} className="flex items-center gap-5 rounded-2xl border border-borda bg-superficie p-4.5">
                  <Capa id={r.livro.id} titulo={r.livro.titulo} autores={[]} capaUrl={r.livro.capaUrl} className="w-[72px] flex-none rounded-lg [&_span]:hidden" />
                  <div className="flex flex-col gap-1">
                    <span className="w-fit rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-semibold text-texto-suave dark:bg-zinc-800">Fila · {r.posicao}º</span>
                    <h2 className="font-semibold">{r.livro.titulo}</h2>
                    <p className="text-sm text-texto-suave">Avisamos quando um exemplar voltar; você terá 48 h para retirar.</p>
                  </div>
                  <BotaoAcao acao={sairDaFila.bind(null, r.id)} rotulo="Sair da fila" pendente="Saindo…" variante="contorno" className="ml-auto" />
                </article>
              ))}
            </>
          )
        )}

        {aba === "historico" && (
          historico.length === 0 ? <Vazio>Nenhum empréstimo devolvido ainda.</Vazio> : (
            <div className="overflow-x-auto rounded-2xl border border-borda bg-superficie">
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-texto-suave">
                  <tr>{["Livro", "Retirado", "Devolvido", "Multa"].map((t) => <th key={t} className="px-4 py-3 font-medium">{t}</th>)}</tr>
                </thead>
                <tbody>
                  {historico.map((e) => (
                    <tr key={e.id} className="border-t border-borda">
                      <td className="px-4 py-3 font-medium">{e.livro.titulo}</td>
                      <td className="px-4 py-3">{dataCurta(e.dataEmprestimo)}</td>
                      <td className="px-4 py-3">{e.dataDevolucao && dataCurta(e.dataDevolucao)}</td>
                      <td className={cn("px-4 py-3", e.multaCentavos > 0 && !e.multaPaga && "font-medium text-perigo")}>
                        {e.multaCentavos === 0 ? "—" : `${reais(e.multaCentavos)}${e.multaPaga ? " · paga" : ""}`}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        )}
      </div>

      <aside aria-label="Sua conta" className="flex w-full flex-[1_1_280px] flex-col gap-4 md:max-w-[360px]">
        <section className="flex flex-col gap-3.5 rounded-2xl border border-borda bg-superficie p-5">
          <strong className="font-semibold">{usuario.login}</strong>
          <div className="flex flex-col gap-1.5">
            <div className="flex justify-between text-sm"><span className="text-texto-suave">Em uso</span><strong>{conta.emUso} de {conta.limite}</strong></div>
            <div className="h-1.5 overflow-hidden rounded-full bg-zinc-100 dark:bg-zinc-800">
              <div className="h-full rounded-full bg-marca" style={{ width: `${(conta.emUso / conta.limite) * 100}%` }} />
            </div>
          </div>
          <div className="flex justify-between border-t border-borda pt-3 text-sm">
            <span className="text-texto-suave">Multa em aberto</span>
            <strong>{multaAberta ? reais(multaAberta) : "Nenhuma"}</strong>
          </div>
        </section>
        <section className="flex flex-col gap-2 rounded-2xl bg-zinc-100 p-5 text-sm text-texto-suave dark:bg-zinc-900">
          <strong className="text-texto">Como funciona</strong>
          <span>Prazo de 14 dias, com uma renovação de 7. Atraso gera multa de R$ 1,00 por dia.</span>
        </section>
      </aside>
    </div>
  );
}

function Vazio({ children }: { children: React.ReactNode }) {
  return <p className="rounded-2xl border border-dashed border-borda px-6 py-12 text-center text-texto-suave">{children}</p>;
}

function CartaoEmprestimo({ emprestimo: e, bloqueado }: { emprestimo: Emprestimo; bloqueado: boolean }) {
  const hoje = hojeIso();
  const total = Math.max(1, diasEntre(e.dataEmprestimo, e.dataPrevista));
  const faltam = diasEntre(hoje, e.dataPrevista);
  const urgente = faltam <= 1;
  const progresso = Math.min(100, Math.max(4, (diasEntre(e.dataEmprestimo, hoje) / total) * 100));
  const situacao = e.atrasado ? `Atrasado ${-faltam} dia(s) · ${reais(-faltam * 100)}` : faltam === 0 ? "Vence hoje" : faltam === 1 ? "Vence amanhã" : `Faltam ${faltam} dias`;

  return (
    <article className="flex flex-wrap gap-5 rounded-2xl border border-borda bg-superficie p-4.5">
      <Capa id={e.livro.id} titulo={e.livro.titulo} autores={[]} capaUrl={e.livro.capaUrl} className="w-[72px] flex-none rounded-lg [&_span]:hidden" />
      <div className="flex min-w-0 flex-[1_1_260px] flex-col gap-3">
        <div className="flex flex-wrap justify-between gap-2">
          <div>
            <h2 className="font-semibold">{e.livro.titulo}</h2>
            <p className="font-mono text-xs text-texto-suave">{e.exemplar}</p>
          </div>
          <span className={cn("h-fit rounded-full border px-2.5 py-0.5 text-xs font-semibold", e.atrasado ? "border-perigo/30 bg-perigo-suave text-perigo" : urgente ? "border-orange-200 bg-alerta-suave text-alerta dark:border-orange-900" : "border-marca-borda bg-marca-suave text-marca-forte")}>
            {situacao}
          </span>
        </div>
        <div className="flex flex-col gap-1.5">
          <div className="h-1.5 overflow-hidden rounded-full bg-zinc-100 dark:bg-zinc-800">
            <div className={cn("h-full rounded-full", e.atrasado ? "bg-red-600" : urgente ? "bg-orange-600" : "bg-marca")} style={{ width: `${progresso}%` }} />
          </div>
          <div className="flex justify-between text-xs text-texto-suave">
            <span>Retirado em {dataCurta(e.dataEmprestimo)}</span>
            <span>Devolver até <strong className="text-texto">{dataCurta(e.dataPrevista)}</strong></span>
          </div>
        </div>
        {e.renovacoes > 0 ? (
          <p className="text-sm text-texto-suave">Já renovado uma vez. Devolva no balcão até o prazo.</p>
        ) : e.atrasado || bloqueado ? (
          <p className="text-sm text-texto-suave">Renovação indisponível enquanto houver pendência.</p>
        ) : (
          <BotaoAcao acao={renovar.bind(null, e.id)} rotulo={<><RefreshCw className="size-4" aria-hidden />Renovar por +7 dias</>} pendente="Renovando…" variante="contorno" className="w-fit" />
        )}
      </div>
    </article>
  );
}
