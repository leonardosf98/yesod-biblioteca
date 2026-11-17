const fuso = "America/Sao_Paulo";

export function dataCurta(dia: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", timeZone: "UTC" }).format(new Date(dia)).replace(".", "");
}

export function dataHora(instante: string) {
  return new Intl.DateTimeFormat("pt-BR", { weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: fuso }).format(new Date(instante));
}

export function reais(centavos: number) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(centavos / 100);
}

export function hojeIso() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: fuso }).format(new Date());
}

export function diasEntre(de: string, ate: string) {
  return Math.round((Date.parse(ate) - Date.parse(de)) / 86_400_000);
}
