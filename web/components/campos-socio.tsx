import { Campo } from "@/components/formulario";
import type { SocioDetalhe } from "@/lib/socios";

export function CamposSocio({ socio }: { socio?: SocioDetalhe }) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <Campo nome="nome" rotulo="Nome" padrao={socio?.nome} required className="sm:col-span-2" />
      <Campo nome="email" rotulo="E-mail (é o login do app)" type="email" padrao={socio?.email} required />
      <Campo nome="telefone" rotulo="Telefone" padrao={socio?.telefone} placeholder="(11) 98888-7777" />
      <Campo nome="cep" rotulo="CEP" padrao={socio?.cep} placeholder="01001-000" />
      <Campo nome="numero" rotulo="Número" padrao={socio?.numero} />
    </div>
  );
}
