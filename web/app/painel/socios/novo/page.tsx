import type { Metadata } from "next";
import { criarSocio } from "@/app/painel/socios/acoes";
import { CamposSocio } from "@/components/campos-socio";
import { Formulario } from "@/components/formulario";
import { TopoPainel } from "@/components/topo-painel";

export const metadata: Metadata = { title: "Novo sócio" };

export default function NovoSocio() {
  return (
    <>
      <TopoPainel titulo="Novo sócio" />
      <main className="p-4 sm:p-7">
        <section className="max-w-2xl rounded-2xl border border-borda bg-superficie p-6">
          <Formulario acao={criarSocio} rotulo="Cadastrar sócio">
            <CamposSocio />
            <p className="text-sm text-texto-suave">Com o CEP, o endereço é preenchido pelo ViaCEP.</p>
          </Formulario>
        </section>
      </main>
    </>
  );
}
