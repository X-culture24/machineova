import type { ParticipantFilter as Filter } from "../api";

export default function ParticipantFilter({ value, onChange }: { value: Filter; onChange: (value: Filter) => void }) {
  return (
    <select className="input" aria-label="Participant type" value={value} onChange={(event) => onChange(event.target.value as Filter)}>
      <option value="">All participants</option>
      <option value="selected">Selected participants</option>
      <option value="general">General participants</option>
    </select>
  );
}
