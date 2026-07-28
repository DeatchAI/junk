import { describe, expect, test } from "bun:test";

import { DocumentArtifactService } from "./DocumentArtifactService";

describe("task-owned browser document artifacts", () => {
  test("parses structured text formats without exposing raw transfer bytes", async () => {
    const service = new DocumentArtifactService();
    const json = await service.ingest("run-docs", {
      url: "https://example.com/data.json",
      mimeType: "application/json; charset=utf-8",
      dataBase64: Buffer.from('{"answer":42}').toString("base64"),
    });
    const csv = await service.ingest("run-docs", {
      url: "https://example.com/data.csv",
      mimeType: "text/csv",
      dataBase64: Buffer.from('name,value\n"alpha, beta",2').toString("base64"),
    });
    const html = await service.ingest("run-docs", {
      url: "https://example.com/report.html",
      mimeType: "text/html",
      dataBase64: Buffer.from("<h1>Report</h1><script>secret()</script><p>Ready &amp; verified</p>").toString("base64"),
    });

    expect(json).toMatchObject({ kind: "json", text: '{\n  "answer": 42\n}' });
    expect(csv).toMatchObject({ kind: "csv", rows: [["name", "value"], ["alpha, beta", "2"]] });
    expect(html).toMatchObject({ kind: "html", text: "Report\n Ready & verified" });
    expect(service.list("run-docs")).toHaveLength(3);
    expect(JSON.stringify(service.list("run-docs"))).not.toContain("dataBase64");
  });

  test("extracts searchable text and metadata from PDFs inside the task boundary", async () => {
    const service = new DocumentArtifactService();
    const pdf = buildPdf("Hello Detach PDF");
    const artifact = await service.ingest("run-pdf", {
      url: "https://example.com/report.pdf",
      mimeType: "application/pdf",
      fileName: "report.pdf",
      dataBase64: pdf.toString("base64"),
    });

    expect(artifact).toMatchObject({ kind: "pdf", pages: 1, fileName: "report.pdf" });
    expect(artifact.text).toContain("Hello Detach PDF");
    service.endTask("run-pdf");
    expect(service.list("run-pdf")).toEqual([]);
  });
});

function buildPdf(text: string) {
  const escaped = text.replace(/[()\\]/g, (value) => `\\${value}`);
  const stream = `BT /F1 12 Tf 72 720 Td (${escaped}) Tj ET`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let body = "%PDF-1.4\n";
  const offsets = [0];
  for (let index = 0; index < objects.length; index += 1) {
    offsets.push(Buffer.byteLength(body));
    body += `${index + 1} 0 obj\n${objects[index]}\nendobj\n`;
  }
  const xrefOffset = Buffer.byteLength(body);
  body += `xref\n0 ${objects.length + 1}\n`;
  body += "0000000000 65535 f \n";
  for (const offset of offsets.slice(1)) body += `${String(offset).padStart(10, "0")} 00000 n \n`;
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
  return Buffer.from(body);
}
