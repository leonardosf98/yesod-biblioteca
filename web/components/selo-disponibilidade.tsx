import { cn } from "@/lib/cn";

export function SeloDisponibilidade({ disponiveis, fila, className }: { disponiveis: number; fila: number; className?: string }) {
  const livre = disponiveis > 0;
  const texto = livre
    ? disponiveis === 1 ? "1 exemplar livre" : `${disponiveis} exemplares livres`
    : fila > 0 ? `Emprestado · fila de ${fila}` : "Emprestado";
  return (
    <span
      className={cn(
        "inline-flex w-fit rounded-full border px-2 py-0.5 text-xs font-medium",
        livre ? "border-marca-borda bg-marca-suave text-marca-forte" : "border-orange-200 bg-alerta-suave text-alerta dark:border-orange-900",
        className,
      )}
    >
      {texto}
    </span>
  );
}
