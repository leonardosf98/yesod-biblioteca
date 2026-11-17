import { Library } from "lucide-react";

export default function Catalogo() {
  return (
    <div className="flex flex-col gap-7">
      <div className="flex flex-col gap-1.5">
        <h1 className="text-3xl font-semibold tracking-tight">Catálogo</h1>
        <p className="text-texto-suave">Escolha um livro e peça pelo app. Você retira no balcão em até 48 h.</p>
      </div>
      <section className="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-borda px-6 py-16 text-center">
        <Library className="size-8 text-marca" aria-hidden />
        <h2 className="text-lg font-semibold">Vitrine em construção</h2>
        <p className="max-w-md text-texto-suave">As capas, a busca e os filtros chegam junto com a API do catálogo.</p>
      </section>
    </div>
  );
}
