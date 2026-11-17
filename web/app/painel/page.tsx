const resumo = ["Empréstimos abertos", "Pedidos para separar", "Atrasados", "Devoluções hoje"];

export default function Painel() {
  return (
    <>
      <header className="border-b border-borda bg-superficie px-7 py-3.5">
        <h1 className="text-lg font-semibold">Painel</h1>
      </header>
      <main className="flex flex-col gap-6 p-7">
        <section aria-label="Resumo" className="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4">
          {resumo.map((rotulo) => (
            <div key={rotulo} className="flex flex-col gap-1.5 rounded-2xl border border-borda bg-superficie p-4.5">
              <span className="text-sm text-texto-suave">{rotulo}</span>
              <strong className="text-3xl font-semibold tracking-tight text-zinc-300 dark:text-zinc-600">—</strong>
            </div>
          ))}
        </section>
        <p className="text-sm text-texto-suave">Os números chegam com o endpoint <code className="font-mono">/api/painel</code>.</p>
      </main>
    </>
  );
}
