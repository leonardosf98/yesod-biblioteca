import type { Metadata } from "next";
import { cancelarPedidoNoBalcao, confirmarRetirada } from "@/app/painel/acoes";
import { BotaoAcao } from "@/components/botao-acao";
import { TopoPainel } from "@/components/topo-painel";
import { dataHora } from "@/lib/formato";
import { buscarPainel } from "@/lib/painel";

export const metadata: Metadata = { title: "Pedidos" };

export default async function Pedidos() {
  const { pedidos } = await buscarPainel();
  return (
    <>
      <TopoPainel titulo="Pedidos para separar" />
      <main className="p-4 sm:p-7">
        <div className="overflow-x-auto rounded-2xl border border-borda bg-superficie">
          <table className="w-full text-sm">
            <thead className="text-left text-xs text-texto-suave">
              <tr>{["Código", "Sócio", "Livro", "Exemplar", "Pedido em", "Retirar até", ""].map((t) => <th key={t} className="px-4 py-3 font-medium">{t}</th>)}</tr>
            </thead>
            <tbody>
              {pedidos.map((p) => (
                <tr key={p.id} className="border-t border-borda">
                  <td className="px-4 py-3 font-mono font-semibold">{p.codigo}</td>
                  <td className="px-4 py-3">{p.socio.nome}</td>
                  <td className="px-4 py-3 font-medium">{p.livro.titulo}</td>
                  <td className="px-4 py-3 font-mono">{p.exemplar}</td>
                  <td className="px-4 py-3 text-texto-suave">{dataHora(p.criadoEm)}</td>
                  <td className="px-4 py-3">{dataHora(p.limiteRetirada)}</td>
                  <td className="px-4 py-2">
                    <div className="flex justify-end gap-2">
                      <BotaoAcao acao={confirmarRetirada.bind(null, p.id)} rotulo="Confirmar retirada" pendente="Confirmando…" variante="contorno" />
                      <BotaoAcao acao={cancelarPedidoNoBalcao.bind(null, p.id)} rotulo="Cancelar" pendente="Cancelando…" variante="fantasma" confirmar={`Cancelar o pedido ${p.codigo}? O sócio será avisado.`} />
                    </div>
                  </td>
                </tr>
              ))}
              {pedidos.length === 0 && <tr><td colSpan={7} className="px-4 py-8 text-center text-texto-suave">Nenhum pedido aguardando retirada.</td></tr>}
            </tbody>
          </table>
        </div>
      </main>
    </>
  );
}
