"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { ResultadoAcao } from "@/components/botao-acao";
import { api, ErroApi } from "@/lib/api";
import { dataHora } from "@/lib/formato";
import { enviar, texto, type EstadoForm } from "@/lib/formulario";

function corpo(dados: FormData) {
  return {
    nome: texto(dados, "nome"),
    email: texto(dados, "email"),
    telefone: texto(dados, "telefone"),
    cep: texto(dados, "cep"),
    numero: texto(dados, "numero"),
  };
}

export async function criarSocio(_: EstadoForm, dados: FormData) {
  return enviar("/api/socios", "POST", dados, corpo(dados), { revalidar: "/painel/socios", destino: (r) => `/painel/socios/${r.id}` });
}

export async function atualizarSocio(id: number, _: EstadoForm, dados: FormData) {
  return enviar(`/api/socios/${id}`, "PUT", dados, corpo(dados), { revalidar: "/painel/socios", ok: "Dados atualizados." });
}

export async function gerarCodigo(id: number): Promise<ResultadoAcao> {
  try {
    const r = await api<{ codigo: string; expiraEm: string }>(`/api/socios/${id}/codigo-ativacao`, { method: "POST" });
    return { ok: `Código ${r.codigo}, válido até ${dataHora(r.expiraEm)}. O sócio ativa em /ativar.` };
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível gerar o código." };
  }
}

export async function excluirSocio(id: number): Promise<ResultadoAcao> {
  try {
    await api(`/api/socios/${id}`, { method: "DELETE" });
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível excluir." };
  }
  revalidatePath("/painel/socios", "layout");
  redirect("/painel/socios");
}

export async function cancelarReserva(reservaId: number): Promise<ResultadoAcao> {
  try {
    await api(`/api/reservas/${reservaId}`, { method: "DELETE" });
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível cancelar." };
  }
  revalidatePath("/painel/socios", "layout");
  return { ok: "Reserva cancelada." };
}

export async function registrarPagamento(emprestimoId: number): Promise<ResultadoAcao> {
  try {
    await api(`/api/emprestimos/${emprestimoId}/pagamento-multa`, { method: "POST" });
  } catch (erro) {
    return { erro: erro instanceof ErroApi ? erro.message : "Não foi possível registrar o pagamento." };
  }
  revalidatePath("/painel", "layout");
  return { ok: "Pagamento registrado." };
}
