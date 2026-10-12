/**
 * National ID numbers are never shown in full: only the last 3 digits, enough to tell people
 * apart (•••••390). Applies to screens and exports alike.
 */
export const maskId = (id?: string | null): string => {
  const d = (id ?? "").replace(/\s+/g, "");
  if (!d) return "—";
  return "•".repeat(Math.max(d.length - 3, 3)) + d.slice(-3);
};
