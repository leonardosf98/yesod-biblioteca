import { BookOpen } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/cn";

export function Marca({ href = "/", subtitulo, className }: { href?: string; subtitulo?: string; className?: string }) {
  return (
    <Link href={href} className={cn("flex items-center gap-2.5", className)}>
      <span className="flex size-8 items-center justify-center rounded-lg bg-marca text-white dark:text-zinc-950">
        <BookOpen className="size-[18px]" aria-hidden />
      </span>
      <span className="flex flex-col leading-tight">
        <span className="text-[17px] font-semibold tracking-tight">Biblioteca</span>
        {subtitulo && <span className="text-xs text-zinc-400">{subtitulo}</span>}
      </span>
    </Link>
  );
}
