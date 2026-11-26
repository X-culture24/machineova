import type { PersonRecord } from "../api";

export const paymentHeaders = ["MobileNumber", "DocumentType", "DocumentNumber", "Amount", "PurposeOfPayment", "Name"];

function mpesaPhone(phone: string | null): string | null {
  const digits = (phone ?? "").replace(/[\s().+-]/g, "");
  const match = /^(?:0|254)?([17]\d{8})$/.exec(digits);
  return match ? "254" + match[1] : null;
}

export function paymentRecipients(rows: Pick<PersonRecord, "phone" | "national_id" | "name">[]) {
  const recipients = new Map<string, { phone: string | null; document: string | number; name: string }>();
  for (const row of rows) {
    const id = row.national_id.trim();
    const phone = mpesaPhone(row.phone);
    const name = row.name.trim();
    const previous = recipients.get(id);
    if (!previous || ((!previous.phone || !previous.name) && phone && name)) {
      recipients.set(id, { phone, document: /^[1-9][0-9]{0,14}$/.test(id) ? Number(id) : id, name });
    }
  }
  const data = [...recipients.values()];
  const invalid = data.filter((p) => !p.phone || !p.name || !/^\d+$/.test(String(p.document))).length;
  if (invalid) throw new Error(`${invalid} recipient(s) have a missing name, invalid ID, or invalid Kenyan mobile number. Correct the check-in details before exporting.`);
  return data;
}

export function paymentRows(data: ReturnType<typeof paymentRecipients>, amount: number, purpose: string) {
  return data.map((p) => [p.phone ?? "", "National Id", p.document, amount, purpose, p.name]);
}

export async function createPaymentPdf(rows: ReturnType<typeof paymentRows>, amount: number, eventName?: string, preview = false) {
  const [{ jsPDF }, { autoTable }] = await Promise.all([import("jspdf"), import("jspdf-autotable")]);
  const doc = new jsPDF({ orientation: "landscape" });
  const currency = new Intl.NumberFormat("en-KE", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const title = preview ? "M-Pesa bulk payment schedule - sample" : "M-Pesa bulk payment schedule";
  const summary = `${rows.length} recipients | Total: KES ${currency.format(rows.length * amount)}`;
  doc.setProperties({ title });
  autoTable(doc, {
    margin: { top: 31, bottom: 16 },
    head: [paymentHeaders],
    body: rows.map((row) => row.map((value, i) => i === 3 ? currency.format(Number(value)) : String(value))),
    styles: { fontSize: 9, cellPadding: 2.4 },
    headStyles: { fillColor: [16, 94, 75] },
    columnStyles: { 3: { halign: "right" } },
    willDrawPage: () => {
      doc.setFontSize(16);
      doc.text(title, 14, 14);
      doc.setFontSize(10);
      doc.text(summary, 14, 26);
      if (eventName) doc.text(doc.splitTextToSize(eventName, 105).slice(0, 2), 283, 15, { align: "right" });
    },
    didDrawPage: ({ pageNumber }) => {
      doc.setFontSize(9);
      if (preview) doc.text("Sample data and amount. For review only.", 14, 201);
      doc.text(`Page ${pageNumber}`, 283, 201, { align: "right" });
    },
  });
  return doc;
}
