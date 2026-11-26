import { kenyanMobile, phoneDigitCount, phoneProblem } from "../phone";

/** A phone input that counts the 10 digits as they are typed. */
export default function PhoneField({ value, onChange, required, label = "Phone number" }: {
  value: string; onChange: (value: string) => void; required?: boolean; label?: string;
}) {
  const count = phoneDigitCount(value);
  const valid = kenyanMobile(value) !== null;
  const problem = phoneProblem(value);
  return (
    <>
      <input type="tel" inputMode="tel" placeholder="07XX XXX XXX" required={required} value={value} aria-label={label}
        aria-invalid={!!problem} onChange={(e) => onChange(e.target.value)} />
      <small className={`phone-count${valid ? " ok" : count > 10 ? " over" : ""}`} aria-live="polite">
        {valid ? "✓ " : ""}{count} / 10 digits{count > 10 ? " — too many" : ""}
      </small>
      {problem && (count >= 10 || /[^0-9+ ().-]/.test(value)) && <small style={{ color: "var(--red)", display: "block" }}>{problem}</small>}
    </>
  );
}
