/** Small line-icon set for KPI cards (24×24, stroke = currentColor). */
const paths: Record<string, string> = {
  ballot: "M4 11h16v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-9Z M8 11V4.5a.5.5 0 0 1 .5-.5h7a.5.5 0 0 1 .5.5V11 M10 7.5l1.4 1.4L14 6.3 M8 15h8",
  chart: "M4 20h16 M7 16v-4 M12 16V8 M17 16v-7",
  pulse: "M3 12h4l2.5-6 4 12L16 12h5",
  station: "M5 21V8l7-5 7 5v13 M9 21v-6h6v6 M3 21h18",
  people: "M16 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 4 18.5V20 M10 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z M20 20v-1.5a3.5 3.5 0 0 0-2.5-3.35 M15.5 4.15a3.5 3.5 0 0 1 0 6.7",
  alert: "M12 3 2.5 19.5h19L12 3Z M12 10v4.5 M12 17.2v.3",
  calendar: "M4 6.5A1.5 1.5 0 0 1 5.5 5h13A1.5 1.5 0 0 1 20 6.5v12a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5v-12Z M4 10h16 M8 3v4 M16 3v4",
  check: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M8 12.2l2.7 2.7L16.2 9.4",
  pin: "M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11Z M12 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z",
  building: "M4 21V5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v16 M15 9h4a1 1 0 0 1 1 1v11 M3 21h18 M8 8h3 M8 12h3 M8 16h3",
  trophy: "M8 4h8v5a4 4 0 0 1-8 0V4Z M8 6H5v1.5A3.5 3.5 0 0 0 8.5 11 M16 6h3v1.5a3.5 3.5 0 0 1-3.5 3.5 M12 13v4 M8.5 20h7 M10 17h4",
  target: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M12 16.5a4.5 4.5 0 1 0 0-9 4.5 4.5 0 0 0 0 9Z M12 12.6a.6.6 0 1 0 0-1.2.6.6 0 0 0 0 1.2Z",
  shield: "M12 3 5 6v5.5c0 4.3 3 8 7 9.5 4-1.5 7-5.2 7-9.5V6l-7-3Z M9 12l2.2 2.2L15.5 10",
  megaphone: "M3 10.5v3a1 1 0 0 0 1 1h2l5 4V5.5l-5 4H4a1 1 0 0 0-1 1Z M15 9a4 4 0 0 1 0 6 M18 6.5a7.5 7.5 0 0 1 0 11",
  clock: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M12 7.5V12l3 2",
  id: "M3.5 6.5A1.5 1.5 0 0 1 5 5h14a1.5 1.5 0 0 1 1.5 1.5v11A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5v-11Z M8.5 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z M5.8 15.5c.5-1.2 1.6-2 2.7-2s2.2.8 2.7 2 M14 9.5h4 M14 13h3",
};

export type IconName = keyof typeof paths;

export function Icon({ name, size = 20, className }: { name: IconName; size?: number; className?: string }) {
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {paths[name]!.split(" M").map((d, i) => <path key={i} d={i === 0 ? d : "M" + d} />)}
    </svg>
  );
}

// Order matters: the first match wins.
const byLabel: [RegExp, IconName][] = [
  [/attention|issue|not registered|uncovered/, "alert"],
  [/turnout|ballot|vote cast/, "ballot"],
  [/leading|winner/, "trophy"],
  [/margin|target|remaining|coverage|rate/, "target"],
  [/report|progress|peak/, "pulse"],
  [/check-?ins?|unique/, "check"],
  [/mobiliz/, "megaphone"],
  [/registered|voters|adults/, "id"],
  [/station|open/, "station"],
  [/agent|member|team|gender|age|people|owner/, "people"],
  [/organization|org /, "building"],
  [/event|active now|closed|today/, "calendar"],
  [/region|boundary|county|constituency|ward/, "pin"],
  [/status/, "shield"],
  [/hour|time/, "clock"],
];

/** Picks an icon from a KPI label ("Turnout so far" → ballot). */
export function iconFor(label: string): IconName {
  const l = label.toLowerCase();
  return byLabel.find(([re]) => re.test(l))?.[1] ?? "chart";
}
