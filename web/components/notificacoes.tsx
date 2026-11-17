import { AlarmClock, Bell, BellRing, BookCheck, CircleAlert, CircleX, Inbox, TimerOff } from "lucide-react";
import Link from "next/link";
import { abrirNotificacao, marcarTodasComoLidas } from "@/app/(socio)/notificacoes/acoes";
import { cn } from "@/lib/cn";
import type { Notificacao } from "@/lib/notificacoes";

const icones: Record<string, typeof Bell> = {
  fila_disponivel: BookCheck,
  pedido_expirando: AlarmClock,
  pedido_expirado: TimerOff,
  pedido_cancelado: CircleX,
  devolucao_vencendo: AlarmClock,
  emprestimo_atrasado: CircleAlert,
  pedido_novo: Inbox,
};

const relativo = new Intl.RelativeTimeFormat("pt-BR", { numeric: "auto" });

function haQuanto(instante: string) {
  const minutos = Math.round((Date.parse(instante) - Date.now()) / 60_000);
  if (Math.abs(minutos) < 60) return relativo.format(minutos, "minute");
  const horas = Math.round(minutos / 60);
  if (Math.abs(horas) < 24) return relativo.format(horas, "hour");
  return relativo.format(Math.round(horas / 24), "day");
}

export function ItemNotificacao({ notificacao, compacto }: { notificacao: Notificacao; compacto?: boolean }) {
  const Icone = icones[notificacao.tipo] ?? Bell;
  const naoLida = !notificacao.lidaEm;
  return (
    <form action={abrirNotificacao.bind(null, notificacao.id, notificacao.link)}>
      <button type="submit" className={cn("flex w-full gap-3 text-left transition-colors hover:bg-fundo", compacto ? "px-3 py-2.5" : "px-4 py-3.5")}>
        <span className={cn("mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full", naoLida ? "bg-marca-suave text-marca-forte" : "bg-zinc-100 text-texto-suave dark:bg-zinc-800")}>
          <Icone className="size-4" aria-hidden />
        </span>
        <span className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className={cn("text-sm leading-snug", naoLida ? "font-semibold" : "font-medium text-texto-suave")}>{notificacao.titulo}</span>
          <span className={cn("text-sm text-texto-suave", compacto && "line-clamp-2")}>{notificacao.texto}</span>
          <span className="text-xs text-texto-suave">{haQuanto(notificacao.criadaEm)}</span>
        </span>
        {naoLida && <span className="mt-2 size-2 shrink-0 rounded-full bg-marca" aria-label="Não lida" />}
      </button>
    </form>
  );
}

export function MarcarTodas({ className }: { className?: string }) {
  return (
    <form action={marcarTodasComoLidas}>
      <button type="submit" className={cn("text-sm font-medium text-marca-forte hover:underline", className)}>Marcar todas como lidas</button>
    </form>
  );
}

export function Sino({ naoLidas, notificacoes, verTodas, className }: {
  naoLidas: number;
  notificacoes: Notificacao[];
  verTodas: string;
  className?: string;
}) {
  const Icone = naoLidas > 0 ? BellRing : Bell;
  return (
    <details className={cn("group relative", className)}>
      <summary
        aria-label={naoLidas > 0 ? `Notificações, ${naoLidas} não lidas` : "Notificações"}
        className="relative flex size-11 cursor-pointer list-none items-center justify-center rounded-xl border border-borda text-texto-suave hover:text-texto group-open:text-texto [&::-webkit-details-marker]:hidden"
      >
        <Icone className="size-[18px]" aria-hidden />
        {naoLidas > 0 && (
          <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-perigo px-1 text-[11px] font-semibold text-white">
            {naoLidas > 9 ? "9+" : naoLidas}
          </span>
        )}
      </summary>
      <div className="absolute right-0 z-20 mt-2 flex w-[min(22rem,calc(100vw-2rem))] flex-col overflow-hidden rounded-2xl border border-borda bg-superficie shadow-xl">
        <div className="flex items-center justify-between border-b border-borda px-3 py-2.5">
          <strong className="text-sm">Notificações</strong>
          {naoLidas > 0 && <MarcarTodas />}
        </div>
        {notificacoes.length === 0 ? (
          <p className="px-3 py-8 text-center text-sm text-texto-suave">Nenhuma notificação.</p>
        ) : (
          <ul className="max-h-96 divide-y divide-borda overflow-y-auto">
            {notificacoes.map((n) => <li key={n.id}><ItemNotificacao notificacao={n} compacto /></li>)}
          </ul>
        )}
        <Link href={verTodas} className="border-t border-borda px-3 py-2.5 text-center text-sm font-medium text-texto-suave hover:text-texto">Ver todas</Link>
      </div>
    </details>
  );
}

export function ListaNotificacoes({ naoLidas, notificacoes }: { naoLidas: number; notificacoes: Notificacao[] }) {
  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-texto-suave">{naoLidas > 0 ? `${naoLidas} não lida${naoLidas > 1 ? "s" : ""}` : "Tudo em dia."}</p>
        {naoLidas > 0 && <MarcarTodas />}
      </div>
      {notificacoes.length === 0 ? (
        <p className="rounded-2xl border border-dashed border-borda px-6 py-14 text-center text-texto-suave">Nenhuma notificação.</p>
      ) : (
        <ul className="divide-y divide-borda overflow-hidden rounded-2xl border border-borda bg-superficie">
          {notificacoes.map((n) => <li key={n.id}><ItemNotificacao notificacao={n} /></li>)}
        </ul>
      )}
    </section>
  );
}
