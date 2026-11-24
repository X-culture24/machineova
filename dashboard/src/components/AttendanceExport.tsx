import { useState, type FormEvent } from "react";
import { api, type PersonRecord } from "../api";
import { area, dateTime } from "../format";
import { ErrorNote, Field, Modal } from "./ui";

function download(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function exportCsv(rows: PersonRecord[], filename: string) {
  const headers = ["Name", "National ID", "Sex", "Phone", "County", "Constituency", "Ward", "Event", "Checked in by", "Checked in at"];
  const escape = (value: string | null) => {
    const text = value ?? "";
    const safe = /^[\s]*[=+@-]|^[\t\r\n]/.test(text) ? "'" + text : text;
    return '"' + safe.replaceAll('"', '""') + '"';
  };
  const data = rows.map((p) => [p.name, p.national_id, p.sex, p.phone, p.county, p.constituency, p.ward, p.group_name, p.by, p.at]);
  download(new Blob(["\ufeff", [headers, ...data].map((line) => line.map(escape).join(",")).join("\r\n")], { type: "text/csv;charset=utf-8" }), filename);
}

async function exportPdf(rows: PersonRecord[], filename: string) {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
  const doc = new jsPDF({ orientation: "landscape" });
  doc.text("Event attendance", 14, 16);
  autoTable(doc, {
    startY: 22,
    head: [["Name", "National ID", "Phone", "Area", "Event", "Checked in by", "Checked in at"]],
    body: rows.map((p) => [p.name, p.national_id, p.phone ?? "", area(p.county, p.constituency, p.ward), p.group_name, p.by, dateTime(p.at)]),
    styles: { fontSize: 8 },
  });
  doc.save(filename);
}

export function mpesaPhone(phone: string | null): string | null {
  const digits = (phone ?? "").replace(/[\s().+-]/g, "");
  const match = /^(?:0|254)?([17]\d{8})$/.exec(digits);
  return match ? "254" + match[1] : null;
}

async function exportMpesa(rows: PersonRecord[], amount: number, purpose: string, filename: string) {
  const recipients = new Map<string, PersonRecord>();
  for (const row of rows) {
    if (!recipients.has(row.national_id)) recipients.set(row.national_id, row);
  }
  const data = Array.from(recipients.values(), (p) => ({
    phone: mpesaPhone(p.phone),
    document: /^(?:[1-9][0-9]{0,14})$/.test(p.national_id) ? Number(p.national_id) : p.national_id,
    name: p.name.trim(),
  }));
  const invalid = data.filter((p) => !p.phone || !p.name || !/^\d+$/.test(String(p.document))).length;
  if (invalid) throw new Error(`${invalid} recipient(s) have a missing name, invalid ID, or invalid Kenyan mobile number. Correct the check-in details before exporting.`);
  const { default: ExcelJS } = await import("exceljs");
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Sheet1");
  sheet.addRow(["MobileNumber", "DocumentType", "DocumentNumber", "Amount", "PurposeOfPayment", "Name"]);
  sheet.getRow(1).font = { bold: true };
  for (const p of data) sheet.addRow([p.phone, "National Id", p.document, amount, purpose, p.name]);
  const bytes = await workbook.xlsx.writeBuffer();
  download(new Blob([new Uint8Array(bytes)], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }), filename);
}

export default function AttendanceExport({ eventId, query }: { eventId?: string; query: string }) {
  const [mpesa, setMpesa] = useState(false);
  const [amount, setAmount] = useState("");
  const [purpose, setPurpose] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function run(format: "csv" | "pdf" | "xlsx") {
    setBusy(true);
    setError(null);
    try {
      const rows = await api.checkins({ event_id: eventId, q: query, export: "true" });
      if (!rows.length) throw new Error("No check-ins match this export.");
      const filename = `attendance-${new Date().toISOString().slice(0, 10)}.${format}`;
      if (format === "csv") exportCsv(rows, filename);
      if (format === "pdf") await exportPdf(rows, filename);
      if (format === "xlsx") {
        await exportMpesa(rows, Number(amount), purpose.trim(), filename);
        setMpesa(false);
      }
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!purpose.trim() || !Number.isFinite(Number(amount)) || Number(amount) <= 0) {
      setError("Enter a positive payment amount and a purpose.");
      return;
    }
    void run("xlsx");
  }

  return (
    <>
      <div className="row gap">
        <button className="btn secondary" disabled={busy} onClick={() => void run("csv")}>Export CSV</button>
        <button className="btn secondary" disabled={busy} onClick={() => void run("pdf")}>Export PDF</button>
        <button className="btn secondary" disabled={busy || !eventId} title={eventId ? undefined : "Select an event first"} onClick={() => { setError(null); setMpesa(true); }}>M-Pesa bulk (.xlsx)</button>
      </div>
      {!mpesa && <ErrorNote error={error} />}
      {mpesa && <Modal title="M-Pesa bulk export" onClose={() => { if (!busy) setMpesa(false); }}>
        <form className="stack" onSubmit={submit}>
          <ErrorNote error={error} />
          <p className="muted">One row per national ID in the selected event and search results.</p>
          <Field label="Amount per person (KES)"><input type="number" required min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
          <Field label="Purpose of payment"><input required value={purpose} onChange={(e) => setPurpose(e.target.value)} /></Field>
          <div className="modal-actions">
            <button type="button" className="btn secondary" disabled={busy} onClick={() => { setError(null); setMpesa(false); }}>Cancel</button>
            <button className="btn" disabled={busy}>{busy ? "Preparing…" : "Download XLSX"}</button>
          </div>
        </form>
      </Modal>}
    </>
  );
}
