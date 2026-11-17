import { cn } from "@/lib/cn";

const cores = ["#1e3a5f", "#7c2d12", "#57534e", "#134e4a", "#312e81", "#713f12", "#831843", "#1e293b", "#365314", "#0c4a6e"];

export function Capa({ id, titulo, autores, capaUrl, className }: {
  id: number;
  titulo: string;
  autores: string[];
  capaUrl: string | null;
  className?: string;
}) {
  const base = cn("aspect-[3/4] w-full overflow-hidden rounded-xl shadow-[0_1px_2px_rgba(0,0,0,.06),0_8px_24px_-12px_rgba(0,0,0,.35)]", className);
  if (capaUrl) {
    return (
      <div className={cn(base, "bg-zinc-200 dark:bg-zinc-800")}>
        <img src={capaUrl} alt={`Capa de ${titulo}`} loading="lazy" className="size-full object-cover" />
      </div>
    );
  }
  return (
    <div className={cn(base, "flex flex-col justify-between p-4 text-white")} style={{ background: cores[id % cores.length] }} aria-hidden>
      <span className="text-lg font-semibold leading-tight tracking-tight">{titulo}</span>
      <span className="border-t border-white/35 pt-2 text-xs opacity-85">{autores.join(", ")}</span>
    </div>
  );
}
