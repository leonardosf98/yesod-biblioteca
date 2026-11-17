import { cn } from "@/lib/cn";

export function Input({ className, ...props }: React.ComponentProps<"input">) {
  return (
    <input
      className={cn(
        "h-11 w-full rounded-xl border border-borda bg-superficie px-3.5 text-[15px] text-texto outline-none placeholder:text-texto-suave focus:border-marca focus:ring-2 focus:ring-marca/20",
        className,
      )}
      {...props}
    />
  );
}
