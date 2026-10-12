const nf = new Intl.NumberFormat("en-KE");
export const num = (n: number) => nf.format(n);
export const pct = (f: number) => `${Math.round(f * 100)}%`;
export const time = (iso: string) =>
  new Date(iso).toLocaleTimeString("en-KE", { hour: "2-digit", minute: "2-digit" });
export const dateTime = (iso: string) =>
  new Date(iso).toLocaleString("en-KE", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
export const date = (iso: string) =>
  new Date(iso).toLocaleDateString("en-KE", { day: "numeric", month: "short", year: "numeric" });
export const hourLabel = (h: number) => `${h % 12 === 0 ? 12 : h % 12} ${h < 12 ? "AM" : "PM"}`;
export const area = (...parts: (string | null | undefined)[]) => parts.filter(Boolean).join(" · ") || "Anywhere";
export const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]!.toUpperCase())
    .join("");
