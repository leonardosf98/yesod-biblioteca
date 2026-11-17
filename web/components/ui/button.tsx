import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/cn";

export const estiloBotao = cva(
  "inline-flex items-center justify-center gap-2 rounded-xl font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-marca disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variante: {
        primario: "bg-marca text-white hover:bg-marca-forte dark:text-zinc-950",
        contorno: "border border-borda bg-superficie text-texto hover:bg-fundo",
        fantasma: "text-texto-suave hover:bg-fundo hover:text-texto",
      },
      tamanho: {
        md: "h-11 px-4 text-sm",
        lg: "h-12 px-5 text-[15px]",
      },
    },
    defaultVariants: { variante: "primario", tamanho: "md" },
  },
);

type Props = React.ComponentProps<"button"> & VariantProps<typeof estiloBotao>;

export function Button({ className, variante, tamanho, ...props }: Props) {
  return <button className={cn(estiloBotao({ variante, tamanho }), className)} {...props} />;
}
