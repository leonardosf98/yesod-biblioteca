import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { atualizarSocio, cancelarReserva, excluirSocio, gerarCodigo } from "@/app/painel/socios/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { CamposSocio } from "@/components/campos-socio";
import { Formulario } from "@/components/formulario";
import { TopoPainel } from "@/components/topo-painel";
import { ErroApi } from "@/lib/api";
import { dataCurta, reais } from "@/lib/formato";
import { buscarSocio } from "@/lib/socios";

export const metadata: Metadata = { title: "Sócio" };

export default async function PaginaSocio({ params }: { params: Promise<{ id: string }> }) {
  const socio = await buscarSocio((await params).id).catch((erro) => {
    if (erro instanceof ErroApi && erro.status === 404) notFound();
    throw erro;
  });
  const endereco = [socio.logradouro, socio.numero, socio.bairro, socio.cidade && `${socio.cidade}/${socio.uf}`].filter(Boolean).join(", ");

  return (
    <>
      <TopoPainel titulo={socio.nome} />
      <main className="flex flex-wrap items-start gap-6 p-4 sm:p-7">
        <div className="flex min-w-0 flex-[3_1_480px] flex-col gap-6">
          <section className="rounded-2xl border border-borda bg-superficie p-6">
            <h2 className="mb-4 font-semibold">Dados</h2>
            <Formulario acao={atualizarSocio.bind(null, socio.id)} rotulo="Salvar">
              <CamposSocio socio={socio} />
              <p className="text-sm text-texto-suave">Endereço: {endereco || "—"}</p>
            </Formulario>
          </section>
          <section className="rounded-2xl border border-borda bg-superficie">
            <h2 className="border-b border-borda px-5 py-4 font-semibold">Empréstimos</h2>
            {socio.emprestimos.length === 0 ? <p className="px-5 py-6 text-sm text-texto-suave">Nenhum empréstimo.</p> : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs text-texto-suave">
                    <tr>{["Livro", "Exemplar", "Retirado", "Prazo", "Devolvido", "Multa"].map((t) => <th key={t} className="px-5 py-2.5 font-medium">{t}</th>)}</tr>
                  </thead>
                  <tbody>
                    {socio.emprestimos.map((e) => (
                      <tr key={e.id} className="border-t border-borda">
                        <td className="px-5 py-3 font-medium">{e.livro ?? "—"}</td>
                        <td className="px-5 py-3 font-mono">{e.exemplar}</td>
                        <td className="px-5 py-3">{dataCurta(e.dataEmprestimo)}</td>
                        <td className="px-5 py-3">{dataCurta(e.dataPrevista)}</td>
                        <td className="px-5 py-3">{e.dataDevolucao ? dataCurta(e.dataDevolucao) : "em aberto"}</td>
                        <td className="px-5 py-3">{e.multaCentavos ? `${reais(e.multaCentavos)}${e.multaPaga ? " · paga" : ""}` : "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </div>
        <aside className="flex w-full flex-[1_1_280px] flex-col gap-4 md:max-w-sm">
          <section className="flex flex-col gap-3 rounded-2xl border border-borda bg-superficie p-5">
            <h2 className="font-semibold">Acesso ao app</h2>
            <p className="text-sm text-texto-suave">{socio.contaAtiva ? "Conta ativa. Um código novo serve para trocar a senha esquecida." : "Ainda sem conta. Gere um código e entregue ao sócio."}</p>
            <BotaoAcao acao={gerarCodigo.bind(null, socio.id)} rotulo="Gerar código de ativação" pendente="Gerando…" variante="contorno" />
          </section>
          {socio.pendencias.length > 0 && (
            <section className="flex flex-col gap-2 rounded-2xl border border-perigo/30 bg-perigo-suave p-5 text-sm text-perigo">
              <h2 className="font-semibold">Pendências</h2>
              {socio.pendencias.map((p) => <p key={p}>{p}</p>)}
            </section>
          )}
          {socio.reservas.length > 0 && (
            <section className="rounded-2xl border border-borda bg-superficie p-5 text-sm">
              <h2 className="mb-2 font-semibold">Na fila de</h2>
              <ul className="flex flex-col gap-2">
                {socio.reservas.map((r) => (
                  <li key={r.id} className="flex items-center justify-between gap-2">
                    <span className="text-texto-suave">{r.livro}</span>
                    <BotaoAcao acao={cancelarReserva.bind(null, r.id)} rotulo="Cancelar" pendente="…" variante="fantasma" />
                  </li>
                ))}
              </ul>
            </section>
          )}
          <BotaoAcao acao={excluirSocio.bind(null, socio.id)} rotulo="Excluir sócio" pendente="Excluindo…" variante="fantasma" className="w-fit" confirmar={`Excluir ${socio.nome}? A conta do app também será apagada.`} />
        </aside>
      </main>
    </>
  );
}
