import { extname } from "node:path";

const MAX_ARTIFACT_BYTES = 25 * 1024 * 1024;
const MAX_ARTIFACTS_PER_TASK = 12;
const MAX_EXTRACTED_TEXT = 500_000;

export interface BrowserArtifactInput {
  url: string;
  mimeType?: string;
  fileName?: string;
  dataBase64: string;
}

export interface BrowserDocumentArtifact {
  id: string;
  runId: string;
  url: string;
  fileName?: string;
  mimeType: string;
  size: number;
  kind: "text" | "json" | "csv" | "html" | "pdf" | "image" | "binary";
  text?: string;
  textTruncated?: boolean;
  pages?: number;
  metadata?: Record<string, unknown>;
  rows?: string[][];
  image?: { data: string; mimeType: string };
  createdAt: number;
}

export class DocumentArtifactService {
  private readonly artifacts = new Map<string, BrowserDocumentArtifact[]>();

  async ingest(runId: string, input: BrowserArtifactInput) {
    if (!runId) throw new Error("A browser task is required to create a document artifact");
    if (!input.dataBase64) throw new Error("The browser returned no document bytes");

    const bytes = Buffer.from(input.dataBase64, "base64");
    if (bytes.byteLength === 0) throw new Error("The browser returned an empty document");
    if (bytes.byteLength > MAX_ARTIFACT_BYTES) {
      throw new Error(`Document is larger than ${Math.round(MAX_ARTIFACT_BYTES / 1024 / 1024)} MB`);
    }

    const mimeType = normalizeMimeType(input.mimeType, input.fileName, input.url);
    const artifact = await parseArtifact({
      id: `browser_artifact_${crypto.randomUUID()}`,
      runId,
      url: input.url,
      fileName: input.fileName,
      mimeType,
      bytes,
    });
    const taskArtifacts = this.artifacts.get(runId) ?? [];
    taskArtifacts.push(artifact);
    if (taskArtifacts.length > MAX_ARTIFACTS_PER_TASK) taskArtifacts.shift();
    this.artifacts.set(runId, taskArtifacts);
    return publicArtifact(artifact);
  }

  list(runId: string) {
    return (this.artifacts.get(runId) ?? []).map(publicArtifact);
  }

  get(runId: string, artifactId: string) {
    const artifact = (this.artifacts.get(runId) ?? []).find((candidate) => candidate.id === artifactId);
    if (!artifact) throw new Error(`No task document artifact found: ${artifactId}`);
    return publicArtifact(artifact);
  }

  endTask(runId: string) {
    this.artifacts.delete(runId);
  }

  clear() {
    this.artifacts.clear();
  }
}

async function parseArtifact(input: {
  id: string;
  runId: string;
  url: string;
  fileName?: string;
  mimeType: string;
  bytes: Buffer;
}): Promise<BrowserDocumentArtifact> {
  const base = {
    id: input.id,
    runId: input.runId,
    url: input.url,
    fileName: input.fileName,
    mimeType: input.mimeType,
    size: input.bytes.byteLength,
    createdAt: Date.now(),
  };

  if (input.mimeType === "application/pdf") {
    const parsed = await parsePdf(input.bytes);
    return {
      ...base,
      kind: "pdf",
      text: parsed.text,
      textTruncated: parsed.textTruncated,
      pages: parsed.pages,
      metadata: parsed.metadata,
    };
  }

  if (input.mimeType.startsWith("image/")) {
    return {
      ...base,
      kind: "image",
      image: { data: input.bytes.toString("base64"), mimeType: input.mimeType },
    };
  }

  const rawText = decodeText(input.bytes);
  if (input.mimeType === "application/json" || input.mimeType.endsWith("+json")) {
    let value: unknown;
    try {
      value = JSON.parse(rawText);
    } catch {
      value = undefined;
    }
    const text = value === undefined ? rawText : JSON.stringify(value, null, 2);
    return { ...base, kind: "json", ...boundedText(text) };
  }

  if (input.mimeType === "text/csv" || input.mimeType === "text/tab-separated-values") {
    const delimiter = input.mimeType === "text/tab-separated-values" ? "\t" : ",";
    const rows = parseDelimited(rawText, delimiter).slice(0, 2_000).map((row) => row.slice(0, 100));
    return { ...base, kind: "csv", ...boundedText(rawText), rows };
  }

  if (input.mimeType === "text/html" || input.mimeType === "application/xhtml+xml") {
    return { ...base, kind: "html", ...boundedText(htmlToText(rawText)) };
  }

  if (input.mimeType.startsWith("text/") || isTextExtension(input.fileName || input.url)) {
    return { ...base, kind: "text", ...boundedText(rawText) };
  }

  return { ...base, kind: "binary" };
}

async function parsePdf(bytes: Buffer) {
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  const loadingTask = pdfjs.getDocument({
    data: new Uint8Array(bytes),
    useSystemFonts: true,
  });
  const document = await loadingTask.promise;
  const pageTexts: string[] = [];
  for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
    const page = await document.getPage(pageNumber);
    const content = await page.getTextContent();
    pageTexts.push(content.items
      .map((item) => "str" in item ? item.str : "")
      .filter(Boolean)
      .join(" ")
      .replace(/\s+/g, " ")
      .trim());
  }
  const metadataResult = await document.getMetadata().catch(() => undefined);
  const bounded = boundedText(pageTexts.map((text, index) => `[Page ${index + 1}]\n${text}`).join("\n\n"));
  return {
    ...bounded,
    pages: document.numPages,
    metadata: metadataResult?.info && typeof metadataResult.info === "object"
      ? sanitizeMetadata(metadataResult.info as Record<string, unknown>)
      : undefined,
  };
}

function publicArtifact(artifact: BrowserDocumentArtifact) {
  return {
    id: artifact.id,
    url: artifact.url,
    fileName: artifact.fileName,
    mimeType: artifact.mimeType,
    size: artifact.size,
    kind: artifact.kind,
    text: artifact.text,
    textTruncated: artifact.textTruncated,
    pages: artifact.pages,
    metadata: artifact.metadata,
    rows: artifact.rows,
    image: artifact.image,
    createdAt: artifact.createdAt,
  };
}

function boundedText(value: string) {
  return {
    text: value.length <= MAX_EXTRACTED_TEXT ? value : value.slice(0, MAX_EXTRACTED_TEXT),
    textTruncated: value.length > MAX_EXTRACTED_TEXT,
  };
}

function normalizeMimeType(mimeType: string | undefined, fileName: string | undefined, url: string) {
  const normalized = mimeType?.split(";")[0]?.trim().toLowerCase();
  if (normalized && normalized !== "application/octet-stream") return normalized;
  const extension = extname(fileName || safeUrlPath(url)).toLowerCase();
  const byExtension: Record<string, string> = {
    ".pdf": "application/pdf",
    ".json": "application/json",
    ".csv": "text/csv",
    ".tsv": "text/tab-separated-values",
    ".txt": "text/plain",
    ".md": "text/markdown",
    ".html": "text/html",
    ".htm": "text/html",
    ".xml": "application/xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
  };
  return byExtension[extension] || normalized || "application/octet-stream";
}

function safeUrlPath(url: string) {
  try {
    return new URL(url).pathname;
  } catch {
    return url;
  }
}

function isTextExtension(value: string) {
  return [".txt", ".md", ".log", ".xml", ".yaml", ".yml", ".js", ".ts", ".py", ".css"]
    .includes(extname(safeUrlPath(value)).toLowerCase());
}

function decodeText(bytes: Buffer) {
  return new TextDecoder("utf-8", { fatal: false }).decode(bytes).replace(/^\uFEFF/, "");
}

function htmlToText(html: string) {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(?:p|div|section|article|li|tr|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;/gi, "'")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function parseDelimited(text: string, delimiter: string) {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index]!;
    if (character === "\"") {
      if (quoted && text[index + 1] === "\"") {
        field += "\"";
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === delimiter && !quoted) {
      row.push(field);
      field = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && text[index + 1] === "\n") index += 1;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += character;
    }
  }
  if (field || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

function sanitizeMetadata(value: Record<string, unknown>) {
  return Object.fromEntries(Object.entries(value).slice(0, 50).map(([key, item]) => [
    key,
    typeof item === "string" || typeof item === "number" || typeof item === "boolean" ? item : String(item ?? ""),
  ]));
}
