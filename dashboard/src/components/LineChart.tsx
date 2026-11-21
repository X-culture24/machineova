// Smooth line chart (SDICS): 2px monotone curves (they never overshoot below zero or above a
// peak), recessive grid, a legend for 2+ series plus a label at each line's end, and a
// crosshair tooltip on hover/touch. Series colours are --series-1.. tokens (styles.css), in a
// fixed order validated for colour-blind separation in light and dark mode.
import { useMemo, useRef, useState, type PointerEvent } from "react";
import { num } from "../format";

export type LineSeries = { name: string; values: (number | null)[] };

/** Monotone cubic (Fritsch–Carlson) path through the points: smooth, no overshoot. */
function smoothPath(pts: { x: number; y: number }[]): string {
  if (pts.length === 0) return "";
  if (pts.length === 1) return `M${pts[0].x},${pts[0].y}`;
  const n = pts.length;
  const dx: number[] = [], m: number[] = [];
  for (let i = 0; i < n - 1; i++) {
    dx.push(pts[i + 1].x - pts[i].x);
    m.push((pts[i + 1].y - pts[i].y) / (dx[i] || 1));
  }
  const t: number[] = [m[0]];
  for (let i = 1; i < n - 1; i++) t.push(m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2);
  t.push(m[n - 2]);
  for (let i = 0; i < n - 1; i++) {
    if (m[i] === 0) { t[i] = 0; t[i + 1] = 0; continue; }
    const a = t[i] / m[i], b = t[i + 1] / m[i], h = a * a + b * b;
    if (h > 9) { const s = 3 / Math.sqrt(h); t[i] = s * a * m[i]; t[i + 1] = s * b * m[i]; }
  }
  let d = `M${pts[0].x},${pts[0].y}`;
  for (let i = 0; i < n - 1; i++) {
    const c = dx[i] / 3;
    d += ` C${pts[i].x + c},${pts[i].y + c * t[i]} ${pts[i + 1].x - c},${pts[i + 1].y - c * t[i + 1]} ${pts[i + 1].x},${pts[i + 1].y}`;
  }
  return d;
}

function niceMax(v: number): number {
  if (v <= 5) return 5;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  const f = v / p;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * p;
}

export function LineChart({ labels, series, height = 200, unit = "", area = true }: {
  labels: string[];
  series: LineSeries[];
  height?: number;
  unit?: string;
  area?: boolean;
}) {
  const W = 640, H = height, L = 36, R = 92, T = 12, B = 26;
  const [hover, setHover] = useState<number | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const max = niceMax(Math.max(1, ...series.flatMap((s) => s.values.map((v) => v ?? 0))));
  const x = (i: number) => L + (labels.length <= 1 ? (W - L - R) / 2 : (i * (W - L - R)) / (labels.length - 1));
  const y = (v: number) => T + (1 - v / max) * (H - T - B);
  const ticks = [0, max / 2, max];
  const lines = useMemo(
    () => series.map((s) => {
      const pts = s.values.map((v, i) => (v == null ? null : { x: x(i), y: y(v) })).filter(Boolean) as { x: number; y: number }[];
      return { pts, d: smoothPath(pts) };
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [series, labels.length, max, H],
  );
  const step = Math.max(1, Math.ceil(labels.length / 8)); // at most ~8 x labels
  // End labels only when they don't collide (the legend always names the lines).
  const ends = lines.map((ln) => ln.pts[ln.pts.length - 1]?.y).filter((v) => v != null).sort((p, q) => p - q);
  const endLabels = series.length > 1 && ends.every((v, i) => i === 0 || v - ends[i - 1] >= 14);

  function onMove(e: PointerEvent<SVGSVGElement>) {
    const r = svgRef.current?.getBoundingClientRect();
    if (!r || labels.length === 0) return;
    const px = ((e.clientX - r.left) / r.width) * W;
    let best = 0;
    for (let i = 1; i < labels.length; i++) if (Math.abs(x(i) - px) < Math.abs(x(best) - px)) best = i;
    setHover(best);
  }

  if (labels.length === 0 || series.every((s) => s.values.every((v) => !v))) {
    return <div className="empty">No activity yet.</div>;
  }
  const tipX = hover == null ? 0 : (x(hover) / W) * 100;
  return (
    <div className="linechart">
      {series.length > 1 && (
        <div className="linechart-legend" aria-hidden>
          {series.map((s, i) => (
            <span key={s.name}><i style={{ background: `var(--series-${i + 1})` }} />{s.name}</span>
          ))}
        </div>
      )}
      <div className="linechart-plot">
        <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} role="img"
          aria-label={series.map((s) => `${s.name}: ${s.values.map((v, i) => `${labels[i]} ${v ?? 0}`).join(", ")}`).join("; ")}
          onPointerMove={onMove} onPointerDown={onMove} onPointerLeave={() => setHover(null)}>
          {ticks.map((t) => (
            <g key={t}>
              <line x1={L} x2={W - R} y1={y(t)} y2={y(t)} className="lc-grid" />
              <text x={L - 6} y={y(t) + 4} className="lc-axis" textAnchor="end">{num(Math.round(t))}</text>
            </g>
          ))}
          {labels.map((lb, i) => (i % step === 0 || i === labels.length - 1) && (
            <text key={lb + i} x={x(i)} y={H - 6} className="lc-axis" textAnchor="middle">{lb}</text>
          ))}
          {area && series.length === 1 && lines[0].pts.length > 1 && (
            <path d={`${lines[0].d} L${lines[0].pts[lines[0].pts.length - 1].x},${y(0)} L${lines[0].pts[0].x},${y(0)} Z`}
              className="lc-area" style={{ fill: "var(--series-1)" }} />
          )}
          {lines.map((ln, i) => (
            <g key={series[i].name}>
              <path d={ln.d} className="lc-line" style={{ stroke: `var(--series-${i + 1})` }} />
              {ln.pts.length === 1 && <circle cx={ln.pts[0].x} cy={ln.pts[0].y} r={4} style={{ fill: `var(--series-${i + 1})` }} className="lc-dot" />}
              {endLabels && ln.pts.length > 0 && (
                <text x={ln.pts[ln.pts.length - 1].x + 8} y={ln.pts[ln.pts.length - 1].y + 4} className="lc-endlabel">{series[i].name}</text>
              )}
            </g>
          ))}
          {hover != null && (
            <g>
              <line x1={x(hover)} x2={x(hover)} y1={T} y2={H - B} className="lc-cross" />
              {series.map((s, i) => s.values[hover] != null && (
                <circle key={s.name} cx={x(hover)} cy={y(s.values[hover] as number)} r={5} className="lc-dot"
                  style={{ fill: `var(--series-${i + 1})` }} />
              ))}
            </g>
          )}
        </svg>
        {hover != null && (
          <div className="lc-tip" style={{ left: `${Math.min(80, Math.max(8, tipX))}%` }}>
            <strong>{labels[hover]}</strong>
            {series.map((s, i) => (
              <div key={s.name}><i style={{ background: `var(--series-${i + 1})` }} />{series.length > 1 ? `${s.name}: ` : ""}{num(s.values[hover] ?? 0)}{unit && ` ${unit}`}</div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
