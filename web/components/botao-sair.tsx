import { LogOut } from "lucide-react";
import { sair } from "@/app/entrar/actions";
import { cn } from "@/lib/cn";

export function BotaoSair({ className }: { className?: string }) {
  return (
    <form action={sair}>
      <button type="submit" aria-label="Sair" className={cn("flex size-11 items-center justify-center rounded-xl", className)}>
        <LogOut className="size-[18px]" aria-hidden />
      </button>
    </form>
  );
}
