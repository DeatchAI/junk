import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import type { AgentRun } from "./AgentAdapter";

export function consumeJsonLines<T>(
  chunk: string,
  onEvent: (event: T) => void,
  previousRemainder = ""
) {
  const combined = `${previousRemainder}${chunk}`;
  const lines = combined.split(/\r?\n/);
  const remainder = lines.pop() ?? "";

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      onEvent(JSON.parse(trimmed) as T);
    } catch {
      // CLIs sometimes mix human-readable lines into structured streams.
    }
  }

  return { remainder };
}

export async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, onTimeout: () => void) {
  let timeoutId: Timer | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeoutId = setTimeout(() => {
          onTimeout();
          reject(new Error(`Agent did not finish within ${Math.round(timeoutMs / 1000)}s`));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
}

export function createTempJsonFile(prefix: string, fileName: string, data: unknown) {
  const dir = mkdtempSync(join(tmpdir(), prefix));
  const path = join(dir, fileName);
  writeFileSync(path, JSON.stringify(data, null, 2));
  return {
    path,
    cleanup() {
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

export function createTempTextFile(prefix: string, fileName: string, contents: string) {
  const dir = mkdtempSync(join(tmpdir(), prefix));
  const path = join(dir, fileName);
  writeFileSync(path, contents);
  return {
    path,
    cleanup() {
      rmSync(dir, { recursive: true, force: true });
    },
  };
}

export function cancellableRejectedRun(message: string): AgentRun {
  return {
    cancel() {},
    finished: Promise.reject(new Error(message)),
  };
}

export function summarizeShellCommand(command?: string) {
  if (!command?.trim()) return "Running a command";

  const cleaned = command.trim().replace(/\s+/g, " ");
  const searchMatch = cleaned.match(/\brg\b.*?["']([^"']{3,80})["']/);
  if (searchMatch?.[1]) return `Searching for "${searchMatch[1]}"`;

  const sedMatch = cleaned.match(/\bsed\s+-n\s+['"]?([^'"]+)['"]?\s+(.+)$/);
  if (sedMatch?.[1]) return `Reading ${shortPath(sedMatch[2] ?? "file")} (${sedMatch[1]})`;

  if (cleaned.includes("git status")) return "Checking repository status";
  if (cleaned.includes("git diff")) return "Reviewing local changes";
  if (cleaned.includes("ls ")) return "Listing files";

  return `Running ${cleaned.length > 90 ? `${cleaned.slice(0, 87)}...` : cleaned}`;
}

export function shortPath(path: string) {
  const trimmed = path.trim().replace(/^["']|["']$/g, "");
  const parts = trimmed.split("/");
  return parts.slice(-2).join("/") || trimmed;
}

export function asStringRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;
}

export function getString(value: unknown) {
  return typeof value === "string" ? value : undefined;
}
