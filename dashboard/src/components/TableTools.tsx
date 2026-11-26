import { useMemo, useState, type ReactNode } from "react";

// Sorting and filtering for every table. Lists that arrive whole are sorted
// and filtered here (useTable); paged lists send the sort to the API
// (useSort + SortTh) so the order covers every page, not just this one.

export type SortDir = "asc" | "desc";
export interface SortState { key: string; dir: SortDir }
type Cell = string | number | boolean | null | undefined;

export interface Column<T> {
  key: string;
  label: ReactNode;
  /** The value the column sorts by; leave out for a column that doesn't sort. */
  sort?: (row: T) => Cell;
  /** Adds a dropdown filter of the column's values. */
  filter?: (row: T) => string | null | undefined;
  /** How a filter value reads in its dropdown. */
  format?: (value: string) => string;
  /** Name of the filter when the heading isn't plain text. */
  filterLabel?: string;
  num?: boolean;
  className?: string;
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

/** Blanks sort last whichever way the column is sorted. */
export function compareCells(a: Cell, b: Cell): number {
  const blankA = a === null || a === undefined || a === "";
  const blankB = b === null || b === undefined || b === "";
  if (blankA || blankB) return blankA === blankB ? 0 : blankA ? 1 : -1;
  if (typeof a === "number" && typeof b === "number") return a - b;
  if (typeof a === "boolean" && typeof b === "boolean") return Number(a) - Number(b);
  return collator.compare(String(a), String(b));
}

export function useSort(initial: SortState | null = null, onChange?: () => void) {
  const [sort, setSort] = useState<SortState | null>(initial);
  const toggle = (key: string, num = false) => {
    setSort((s) => (s?.key === key ? { key, dir: s.dir === "asc" ? "desc" : "asc" } : { key, dir: num ? "desc" : "asc" }));
    onChange?.();
  };
  return { sort, setSort, toggle, params: sort ? { sort: sort.key, dir: sort.dir } : {} };
}

/** A heading that sorts its column; click again to reverse. */
export function SortTh({ label, sortKey, sort, onSort, num, className }: {
  label: ReactNode; sortKey: string; sort: SortState | null; onSort: (key: string, num?: boolean) => void; num?: boolean; className?: string;
}) {
  const on = sort?.key === sortKey;
  return (
    <th className={className ?? (num ? "num" : undefined)} aria-sort={on ? (sort!.dir === "asc" ? "ascending" : "descending") : "none"}>
      <button type="button" className="th-sort" onClick={() => onSort(sortKey, num)} title="Sort">
        {label}<span className={`sort-mark${on ? " on" : ""}`} aria-hidden>{on ? (sort!.dir === "asc" ? "▲" : "▼") : "↕"}</span>
      </button>
    </th>
  );
}

export function useTable<T>(rows: readonly T[] | null | undefined, columns: (Column<T> | false | null | undefined)[], initial: SortState | null = null) {
  const cols = columns.filter(Boolean) as Column<T>[];
  const { sort, setSort, toggle } = useSort(initial);
  const [filters, setFilters] = useState<Record<string, string>>({});
  const all = rows ?? [];

  const options = useMemo(() => {
    const out: Record<string, { value: string; count: number }[]> = {};
    for (const c of cols) {
      if (!c.filter) continue;
      const counts = new Map<string, number>();
      for (const r of all) {
        const v = c.filter(r);
        if (v !== null && v !== undefined && v !== "") counts.set(v, (counts.get(v) ?? 0) + 1);
      }
      out[c.key] = [...counts].map(([value, count]) => ({ value, count })).sort((a, b) => collator.compare(a.value, b.value));
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [all, cols.map((c) => c.key).join()]);

  const shown = useMemo(() => {
    let out = all.filter((r) => cols.every((c) => !c.filter || !filters[c.key] || c.filter(r) === filters[c.key]));
    const col = sort && cols.find((c) => c.key === sort.key);
    if (col?.sort) {
      const by = col.sort;
      const sign = sort!.dir === "asc" ? 1 : -1;
      out = [...out].sort((a, b) => {
        const va = by(a), vb = by(b);
        const blank = (v: Cell) => v === null || v === undefined || v === "";
        if (blank(va) || blank(vb)) return compareCells(va, vb); // blanks stay last
        return sign * compareCells(va, vb);
      });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [all, sort?.key, sort?.dir, JSON.stringify(filters)]);

  const active = Object.values(filters).some(Boolean);
  const head = (
    <tr>
      {cols.map((c) => (c.sort
        ? <SortTh key={c.key} label={c.label} sortKey={c.key} sort={sort} onSort={toggle} num={c.num} className={c.className} />
        : <th key={c.key} className={c.className ?? (c.num ? "num" : undefined)}>{c.label}</th>))}
    </tr>
  );
  const usable = cols.filter((c) => c.filter && ((options[c.key]?.length ?? 0) > 1 || filters[c.key]));
  const filterBar = usable.length === 0 ? null : (
    <div className="toolbar table-filters" aria-label="Filter the table">
      {usable.map((c) => {
        const name = c.filterLabel ?? (typeof c.label === "string" ? c.label : c.key);
        return (
          <select key={c.key} className="input" aria-label={`Filter by ${name}`} value={filters[c.key] ?? ""}
            onChange={(e) => setFilters((f) => ({ ...f, [c.key]: e.target.value }))}>
            <option value="">{`All · ${name.toLowerCase()}`}</option>
            {(options[c.key] ?? []).map((o) => <option key={o.value} value={o.value}>{`${c.format ? c.format(o.value) : o.value} (${o.count.toLocaleString()})`}</option>)}
          </select>
        );
      })}
      {active && <button type="button" className="btn ghost small" onClick={() => setFilters({})}>Clear filters</button>}
      {active && <small className="muted" style={{ alignSelf: "center" }}>{shown.length.toLocaleString()} of {all.length.toLocaleString()}</small>}
    </div>
  );
  return { rows: shown, head, filterBar, sort, setSort, toggle, filtered: active };
}
