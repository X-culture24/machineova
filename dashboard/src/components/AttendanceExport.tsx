import { useState, type FormEvent } from "react";
import { api, type CheckinQuery, type ParticipantFilter, type PersonRecord } from "../api";
import { dateTime } from "../format";
import { createPaymentPdf, paymentHeaders, paymentRecipients, paymentRows } from "./paymentExport";
import ParticipantTypeFilter from "./ParticipantFilter";
import { ErrorNote, Field, Modal } from "./ui";

function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const columns = [
  { label: "Name", read: (p: PersonRecord) => p.name },
  { label: "National ID", read: (p: PersonRecord) => p.national_id },
  { label: "Sex", read: (p: PersonRecord) => p.sex },
  { label: "Phone", read: (p: PersonRecord) => p.phone },
  { label: "County", read: (p: PersonRecord) => p.county },
  { label: "Constituency", read: (p: PersonRecord) => p.constituency },
  { label: "Ward", read: (p: PersonRecord) => p.ward },
  { label: "Event", read: (p: PersonRecord) => p.group_name },
  { label: "Participant type", read: (p: PersonRecord) => p.selected_participant ? "Selected participant" : "General participant" },
  { label: "Checked in by", read: (p: PersonRecord) => p.by },
  { label: "Checked in at", read: (p: PersonRecord) => p.at },
];

function exportCsv(rows: PersonRecord[], filename: string, fields: typeof columns) {
  const headers = fields.map((field) => field.label);
  const escape = (value: string | null) => {
    const text = value ?? "";
    const safe = /^[\s]*[=+@-]|^[\t\r\n]/.test(text) ? "'" + text : text;
    return '"' + safe.replaceAll('"', '""') + '"';
  };
  const data = rows.map((p) => fields.map((field) => field.read(p)));
  download(new Blob(["\ufeff", [headers, ...data].map((line) => line.map(escape).join(",")).join("\r\n")], { type: "text/csv;charset=utf-8" }), filename);
}

async function exportPdf(rows: PersonRecord[], filename: string, fields: typeof columns) {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
  const doc = new jsPDF({ orientation: "landscape" });
  doc.text("Event attendance", 14, 16);
  autoTable(doc, {
    startY: 22,
    head: [fields.map((field) => field.label)],
    body: rows.map((p) => fields.map((field) => field.label === "Checked in at" ? dateTime(p.at) : field.read(p) ?? "")),
    styles: { fontSize: 8 },
  });
  doc.save(filename);
}

async function exportMpesa(rows: PersonRecord[], amount: number, purpose: string, filename: string, format: "xlsx" | "pdf", eventName?: string) {
  const data = paymentRecipients(rows);
  const payments = paymentRows(data, amount, purpose);
  if (format === "pdf") {
    const doc = await createPaymentPdf(payments, amount, eventName);
    doc.save(filename);
    return;
  }
  const { default: ExcelJS } = await import("exceljs");
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Sheet1");
  sheet.addRow([...paymentHeaders]);
  sheet.getRow(1).font = { bold: true };
  for (const row of payments) sheet.addRow(row);
  const bytes = await workbook.xlsx.writeBuffer();
  download(new Blob([new Uint8Array(bytes)], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), filename);
}

export default function AttendanceExport({ eventId, eventName, query, participants = "", filters = {} }: { eventId?: string; eventName?: string; query: string; participants?: ParticipantFilter; filters?: CheckinQuery }) {
  const [dialog, setDialog] = useState<"normal" | "mpesa" | null>(null);
  const [format, setFormat] = useState<"csv" | "pdf">("csv");
  const [paymentFormat, setPaymentFormat] = useState<"xlsx" | "pdf">("xlsx");
  const [scope, setScope] = useState<ParticipantFilter>("");
  const [labels, setLabels] = useState(() => columns.map((column) => column.label));
  const [amount, setAmount] = useState("");
  const [purpose, setPurpose] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function open(kind: "normal" | "mpesa") {
    setError(null);
    setScope(participants);
    setDialog(kind);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const fileType = dialog === "mpesa" ? paymentFormat : format;
    const fields = columns.filter((column) => labels.includes(column.label));
    if (dialog === "normal" && !fields.length) {
      setError("Choose at least one column.");
      return;
    }
    if (dialog === "mpesa" && (!purpose.trim() || !Number.isFinite(Number(amount)) || Number(amount) <= 0)) {
      setError("Enter a positive payment amount and a purpose.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const rows = await api.checkins({ ...filters, event_id: eventId, q: query, participants: scope, export: "true" });
      if (!rows.length) throw new Error("No check-ins match this export.");
      const prefix = dialog === "mpesa" ? "mpesa-payments" : "attendance";
      const filename = `${prefix}-${new Date().toISOString().slice(0, 10)}.${fileType}`;
      if (dialog === "mpesa") {
        await exportMpesa(rows, Number(amount), purpose.trim(), filename, paymentFormat, eventName);
      } else if (format === "csv") {
        exportCsv(rows, filename, fields);
      } else {
        await exportPdf(rows, filename, fields);
      }
      setDialog(null);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div className="row gap">
        <button type="button" className="btn secondary" disabled={busy} onClick={() => open("normal")}>Export</button>
        <button type="button" className="btn secondary" disabled={busy || !eventId} title={eventId ? undefined : "Select an event first"} onClick={() => open("mpesa")}>M-Pesa bulk</button>
      </div>
      {dialog && <Modal title={dialog === "normal" ? "Normal export" : "M-Pesa bulk export"} onClose={() => { if (!busy) setDialog(null); }}>
        <form className="stack" onSubmit={submit}>
          <ErrorNote error={error} />
          <ParticipantTypeFilter value={scope} onChange={setScope} />
          <label className="row gap">
            <input type="checkbox" checked={scope === "selected"} onChange={(e) => setScope(e.target.checked ? "selected" : "")} />
            Selected participants only
          </label>
          {dialog === "normal" ? <>
            <Field label="File format">
              <select value={format} onChange={(e) => setFormat(e.target.value === "pdf" ? "pdf" : "csv")}>
                <option value="csv">CSV</option>
                <option value="pdf">PDF</option>
              </select>
            </Field>
            <fieldset>
              <legend>Columns to include</legend>
              <div className="form-grid">
                {columns.map(({ label }) => <label key={label} className="row gap">
                  <input type="checkbox" checked={labels.includes(label)}
                    onChange={(e) => setLabels((current) => e.target.checked ? [...current, label] : current.filter((field) => field !== label))} />
                  {label}
                </label>)}
              </div>
            </fieldset>
          </> : <>
            <Field label="File format">
              <select value={paymentFormat} onChange={(e) => setPaymentFormat(e.target.value === "pdf" ? "pdf" : "xlsx")}>
                <option value="xlsx">Excel (.xlsx) for upload</option>
                <option value="pdf">PDF payment schedule</option>
              </select>
            </Field>
            <p className="muted">One payment row per national ID.</p>
            <Field label="Amount per person (KES)"><input type="number" required min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
            <Field label="Purpose of payment"><input required value={purpose} onChange={(e) => setPurpose(e.target.value)} /></Field>
          </>}
          <div className="modal-actions">
            <button type="button" className="btn secondary" disabled={busy} onClick={() => setDialog(null)}>Cancel</button>
            <button className="btn" disabled={busy}>{busy ? "Preparing…" : "Download"}</button>
          </div>
        </form>
      </Modal>}
    </>
  );
}
