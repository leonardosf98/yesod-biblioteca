import { CheckCircle2 } from "lucide-react";
import { confirmarRetirada, registrarDevolucao } from "@/app/painel/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { TopoPainel } from "@/components/topo-painel";
import { dataCurta, dataHora, reais } from "@/lib/formato";
import { buscarPainel } from "@/lib/painel";

export default async function Painel() {
  const { resumo, pedidos, atrasados, devolucoesHoje } = await buscarPainel();
  const cartoes = [
    { rotulo: "Empréstimos abertos", valor: resumo.abertos, detalhe: `de ${resumo.exemplares} exemplares`, cor: "" },
    { rotulo: "Pedidos para separar", valor: resumo.pedidos, detalhe: "retirada em até 48 h", cor: "text-marca" },
    { rotulo: "Atrasados", valor: resumo.atrasados, detalhe: `${reais(resumo.multaAtrasadosCentavos)} em multas previstas`, cor: resumo.atrasados ? "text-red-700 dark:text-red-400" : "" },
    { rotulo: "Devoluções hoje", valor: resumo.devolucoesHoje, detalhe: "prazo vence hoje", cor: "" },
  ];

  return (
    <>
      <TopoPainel titulo="Painel" />
      <main className="flex flex-col gap-6 p-4 sm:p-7">
        <section aria-label="Resumo" className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4">
          {cartoes.map((c) => (
            <div key={c.rotulo} className="flex flex-col gap-1.5 rounded-2xl border border-borda bg-superficie p-4.5">
              <span className="text-sm text-texto-suave">{c.rotulo}</span>
              <strong className={`text-3xl font-semibold tracking-tight ${c.cor}`}>{c.valor}</strong>
              <span className="text-xs text-texto-suave">{c.detalhe}</span>
            </div>
          ))}
        </section>

        <div className="flex flex-wrap items-start gap-6">
          <section aria-labelledby="pedidos-t" className="min-w-0 flex-[3_1_420px] rounded-2xl border border-borda bg-superficie">
            <div className="flex items-center justify-between border-b border-borda px-4.5 py-4">
              <h2 id="pedidos-t" className="font-semibold">Pedidos para separar</h2>
              <span className="text-sm text-texto-suave">Confirme quando o sócio retirar</span>
            </div>
            {pedidos.length === 0 ? (
              <p className="flex items-center gap-2 px-4.5 py-6 text-sm text-texto-suave"><CheckCircle2 className="size-4 text-marca" aria-hidden />Nenhum pedido aguardando.</p>
            ) : (
              <ul className="divide-y divide-borda">
                {pedidos.map((p) => (
                  <li key={p.id} className="flex flex-wrap items-center gap-x-4 gap-y-3 px-4.5 py-3.5">
                    <div className="min-w-0 flex-[1_1_220px]">
                      <strong className="block font-semibold">{p.livro.titulo}</strong>
                      <span className="text-sm text-texto-suave">
                        {p.socio.nome} · <span className="font-mono">{p.exemplar}</span> · código <span className="font-mono font-semibold text-texto">{p.codigo}</span>
                      </span>
                      <span className="block text-xs text-texto-suave">Retirar até {dataHora(p.limiteRetirada)}</span>
                    </div>
                    <BotaoAcao acao={confirmarRetirada.bind(null, p.id)} rotulo="Confirmar retirada" pendente="Confirmando…" variante="contorno" />
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section aria-labelledby="atraso-t" className="min-w-0 flex-[2_1_300px] rounded-2xl border border-borda bg-superficie">
            <h2 id="atraso-t" className="border-b border-borda px-4.5 py-4 font-semibold">Atrasados</h2>
            {atrasados.length === 0 ? (
              <p className="px-4.5 py-6 text-sm text-texto-suave">Nenhum atraso.</p>
            ) : (
              <ul className="divide-y divide-borda text-sm">
                {atrasados.map((e) => (
                  <li key={e.emprestimoId} className="flex justify-between gap-3 px-4.5 py-3.5">
                    <div><strong className="block font-semibold">{e.socio.nome}</strong><span className="text-texto-suave">{e.livro.titulo}</span></div>
                    <div className="text-right"><strong className="block font-semibold text-red-700 dark:text-red-400">{e.diasAtraso} dia(s)</strong><span className="text-texto-suave">{reais(e.multaCentavos)}</span></div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <section aria-labelledby="dev-t" className="rounded-2xl border border-borda bg-superficie">
          <h2 id="dev-t" className="border-b border-borda px-4.5 py-4 font-semibold">Devoluções previstas para hoje</h2>
          {devolucoesHoje.length === 0 ? (
            <p className="px-4.5 py-6 text-sm text-texto-suave">Nenhuma devolução prevista para hoje.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="text-left text-xs text-texto-suave">
                  <tr>{["Sócio", "Livro", "Exemplar", "Prazo", ""].map((t) => <th key={t} className="px-4.5 py-2.5 font-medium">{t}</th>)}</tr>
                </thead>
                <tbody>
                  {devolucoesHoje.map((e) => (
                    <tr key={e.emprestimoId} className="border-t border-borda">
                      <td className="px-4.5 py-3 font-medium">{e.socio.nome}</td>
                      <td className="px-4.5 py-3">{e.livro.titulo}</td>
                      <td className="px-4.5 py-3 font-mono">{e.exemplar}</td>
                      <td className="px-4.5 py-3">{dataCurta(e.dataPrevista)}</td>
                      <td className="px-4.5 py-2"><BotaoAcao acao={registrarDevolucao.bind(null, e.emprestimoId)} rotulo="Registrar devolução" pendente="Registrando…" variante="fantasma" /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </main>
    </>
  );
}
