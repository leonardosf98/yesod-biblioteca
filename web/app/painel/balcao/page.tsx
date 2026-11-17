import { Barcode, CheckCircle2, Search } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { devolverNoBalcao, registrarEmprestimo } from "@/app/painel/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { TopoPainel } from "@/components/topo-painel";
import { cn } from "@/lib/cn";
import { dataCurta, reais } from "@/lib/formato";
import { buscarSocios, consultarExemplar, type SocioBalcao } from "@/lib/painel";

export const metadata: Metadata = { title: "Balcão" };

type Props = { searchParams: Promise<{ busca?: string; socio?: string; exemplar?: string; devolver?: string; ok?: string; multa?: string }> };

export default async function Balcao({ searchParams }: Props) {
  const { busca = "", socio = "", exemplar = "", devolver = "", ok = "", multa = "0" } = await searchParams;
  const [{ socios, limite }, consulta, devolucao] = await Promise.all([
    buscarSocios(busca),
    exemplar ? consultarExemplar(exemplar) : null,
    devolver ? consultarExemplar(devolver) : null,
  ]);
  const escolhido = socios.find((s) => String(s.id) === socio);
  const link = (extra: Record<string, string>) => `/painel/balcao?${new URLSearchParams({ busca, socio, exemplar, ...extra })}`;
  const podeEmprestar = ok !== "emprestimo" && escolhido && escolhido.pendencias.length === 0 && escolhido.emUso < limite && consulta?.exemplar.disponivel;

  return (
    <>
      <TopoPainel titulo="Balcão" />
      <main className="flex flex-wrap items-start gap-6 p-4 sm:p-7">
        {ok === "emprestimo" && consulta?.emprestimo && (
          <Aviso>
            Empréstimo registrado: <strong>{consulta.livro.titulo}</strong> com {consulta.emprestimo.socio.nome}, devolver até {dataCurta(consulta.emprestimo.dataPrevista)}.
          </Aviso>
        )}
        {ok === "devolucao" && devolucao && (
          <Aviso>
            Devolução de <strong>{devolucao.livro.titulo}</strong> registrada.{" "}
            {Number(multa) > 0 ? <>Multa de <strong>{reais(Number(multa))}</strong>: cobre agora e registre o pagamento na página do sócio.</> : "Sem multa."}
          </Aviso>
        )}
        <section aria-labelledby="emp-t" className="flex min-w-0 flex-[3_1_440px] flex-col gap-5 rounded-2xl border border-borda bg-superficie p-6">
          <h2 id="emp-t" className="text-xl font-semibold tracking-tight">Novo empréstimo</h2>

          <div className="flex flex-col gap-2">
            <Passo numero={1} feito={Boolean(escolhido)}>Sócio</Passo>
            {escolhido ? (
              <div className="flex flex-wrap items-center gap-3 rounded-xl border border-borda p-3.5">
                <div className="flex-[1_1_180px]">
                  <strong className="block font-semibold">{escolhido.nome}</strong>
                  <span className="text-sm text-texto-suave">{escolhido.email}{escolhido.contaAtiva ? " · conta ativa no app" : ""}</span>
                </div>
                <Selo ok={escolhido.emUso < limite}>{escolhido.emUso} de {limite} em uso</Selo>
                <Selo ok={escolhido.pendencias.length === 0}>{escolhido.pendencias.length ? "Com pendência" : "Sem pendência"}</Selo>
                <Link href={link({ socio: "" })} className="text-sm font-medium text-texto-suave hover:text-texto">Trocar</Link>
                {escolhido.pendencias.map((p) => <p key={p} className="w-full text-sm text-perigo">{p}</p>)}
              </div>
            ) : (
              <>
                <form className="flex h-11 items-center gap-2 rounded-xl border border-borda px-3 focus-within:border-marca">
                  <Search className="size-4 text-texto-suave" aria-hidden />
                  <label htmlFor="busca-socio" className="sr-only">Buscar sócio</label>
                  <input id="busca-socio" name="busca" defaultValue={busca} placeholder="Nome ou e-mail do sócio" className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-texto-suave" />
                  <input type="hidden" name="exemplar" value={exemplar} />
                </form>
                <ul className="divide-y divide-borda rounded-xl border border-borda text-sm">
                  {socios.slice(0, 6).map((s) => <LinhaSocio key={s.id} socio={s} href={link({ socio: String(s.id) })} />)}
                  {socios.length === 0 && <li className="px-3.5 py-3 text-texto-suave">Nenhum sócio encontrado.</li>}
                </ul>
              </>
            )}
          </div>

          <div className="flex flex-col gap-2">
            <Passo numero={2} feito={Boolean(consulta)}>Exemplar</Passo>
            <form className="flex h-13 items-center gap-2.5 rounded-xl border-2 border-marca px-3.5">
              <Barcode className="size-5 text-marca" aria-hidden />
              <label htmlFor="codigo-ex" className="sr-only">Código do exemplar</label>
              <input id="codigo-ex" name="exemplar" defaultValue={exemplar} placeholder="Leia ou digite o código" className="min-w-0 flex-1 bg-transparent font-mono text-lg font-semibold uppercase tracking-wide outline-none placeholder:font-sans placeholder:text-base placeholder:font-normal placeholder:normal-case placeholder:tracking-normal placeholder:text-texto-suave" />
              <input type="hidden" name="busca" value={busca} />
              <input type="hidden" name="socio" value={socio} />
            </form>
            {exemplar && !consulta && <p className="text-sm text-perigo">Nenhum exemplar com o código {exemplar.toUpperCase()}.</p>}
            {consulta && (
              <div className="flex items-center justify-between gap-3 rounded-xl bg-fundo px-3.5 py-3">
                <div>
                  <strong className="block font-semibold">{consulta.livro.titulo}</strong>
                  <span className="text-sm text-texto-suave">Estado {consulta.exemplar.estado}</span>
                </div>
                <Selo ok={consulta.exemplar.disponivel}>{consulta.exemplar.disponivel ? "Na estante" : consulta.emprestimo ? `Com ${consulta.emprestimo.socio.nome}` : "Indisponível"}</Selo>
              </div>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-4 border-t border-borda pt-4">
            <Passo numero={3} feito={false}>Confirmar</Passo>
            <span className="flex-1 text-sm text-texto-suave">Prazo de 14 dias a partir de hoje.</span>
            {podeEmprestar ? (
              <BotaoAcao key={`${socio}-${exemplar}`} acao={registrarEmprestimo.bind(null, escolhido.id, consulta.exemplar.id, consulta.exemplar.codigo)} rotulo="Registrar empréstimo" pendente="Registrando…" tamanho="lg" />
            ) : (
              <span className="text-sm text-texto-suave">Escolha um sócio sem pendência e um exemplar na estante.</span>
            )}
          </div>
        </section>

        <section aria-labelledby="dev-t" className="flex min-w-0 flex-[2_1_300px] flex-col gap-4 rounded-2xl border border-borda bg-superficie p-6">
          <h2 id="dev-t" className="text-xl font-semibold tracking-tight">Devolução rápida</h2>
          <form className="flex flex-col gap-1.5">
            <label htmlFor="codigo-dev" className="text-sm font-medium">Código do exemplar</label>
            <input id="codigo-dev" name="devolver" defaultValue={devolver} className="h-12 rounded-xl border border-borda bg-superficie px-3.5 font-mono text-base font-semibold uppercase outline-none focus:border-marca" />
          </form>
          {devolver && !devolucao && <p className="text-sm text-perigo">Nenhum exemplar com esse código.</p>}
          {devolucao && !devolucao.emprestimo && ok !== "devolucao" && <p className="text-sm text-texto-suave">{devolucao.livro.titulo}: esse exemplar não está emprestado.</p>}
          {devolucao?.emprestimo && (
            <>
              <div className={cn("flex flex-col gap-2 rounded-xl border p-3.5", devolucao.emprestimo.multaCentavos ? "border-perigo/30 bg-perigo-suave" : "border-borda bg-fundo")}>
                <div>
                  <strong className="block font-semibold">{devolucao.livro.titulo}</strong>
                  <span className="text-sm text-texto-suave">{devolucao.emprestimo.socio.nome} · devolver até {dataCurta(devolucao.emprestimo.dataPrevista)}</span>
                </div>
                {devolucao.emprestimo.multaCentavos > 0 && (
                  <div className="flex justify-between text-sm text-perigo"><span>Em atraso</span><strong>{reais(devolucao.emprestimo.multaCentavos)}</strong></div>
                )}
              </div>
              <BotaoAcao key={devolver} acao={devolverNoBalcao.bind(null, devolucao.emprestimo.id, devolucao.exemplar.codigo)} rotulo="Registrar devolução" pendente="Registrando…" />
            </>
          )}
          <p className="text-sm text-texto-suave">Se houver fila para o livro, o próximo sócio já pode pedir pelo app.</p>
        </section>
      </main>
    </>
  );
}

function Passo({ numero, feito, children }: { numero: number; feito: boolean; children: React.ReactNode }) {
  return (
    <span className="flex items-center gap-2 text-sm font-medium">
      <span className={cn("flex size-6 items-center justify-center rounded-full text-xs font-semibold", feito ? "bg-marca text-white dark:text-zinc-950" : "bg-zinc-200 text-texto dark:bg-zinc-800")}>{numero}</span>
      {children}
    </span>
  );
}

function Selo({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return (
    <span className={cn("rounded-full border px-2.5 py-0.5 text-xs font-semibold", ok ? "border-marca-borda bg-marca-suave text-marca-forte" : "border-orange-200 bg-alerta-suave text-alerta dark:border-orange-900")}>
      {children}
    </span>
  );
}

function LinhaSocio({ socio, href }: { socio: SocioBalcao; href: string }) {
  return (
    <li>
      <Link href={href} className="flex items-center justify-between gap-3 px-3.5 py-2.5 hover:bg-fundo">
        <span><strong className="font-medium">{socio.nome}</strong> <span className="text-texto-suave">· {socio.email}</span></span>
        {socio.pendencias.length > 0 && <span className="text-xs font-semibold text-alerta">Pendência</span>}
      </Link>
    </li>
  );
}

function Aviso({ children }: { children: React.ReactNode }) {
  return (
    <p role="status" className="flex w-full items-start gap-2.5 rounded-xl border border-marca-borda bg-marca-suave px-4 py-3 text-sm text-marca-forte">
      <CheckCircle2 className="mt-0.5 size-4 flex-none" aria-hidden />
      <span>{children}</span>
    </p>
  );
}
