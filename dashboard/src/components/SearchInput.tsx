export default function SearchInput({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return <input type="search" className="input" aria-label={label} placeholder={label + "…"} value={value} onChange={(event) => onChange(event.target.value)} />;
}

export function matchesSearch(query: string, ...values: (string | null | undefined)[]) {
  const text = query.trim().toLowerCase();
  return !text || values.some((value) => value?.toLowerCase().includes(text));
}
