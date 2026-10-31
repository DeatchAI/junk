import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { captureFile, git, MAX_FILE_BYTES } from "./GitRepository";
import { missingImage, type FileChange, type FileImage, type Repository } from "./GitTypes";

export async function fileChange(path: string, before: FileImage, after: FileImage): Promise<FileChange> {
  const base = { path, status: before.kind === "missing" ? "Added" : after.kind === "missing" ? "Deleted" : "Modified",
    additions: 0, deletions: 0, binary: false, diff: "" };
  if (before.kind === "unsupported" || after.kind === "unsupported") {
    let reason = before.reason ?? after.reason;
    if (reason === "This file exceeds the local snapshot size limit." && Math.max(before.size, after.size) <= MAX_FILE_BYTES)
      reason = "This older session snapshot exhausted its shared budget. The historical contents of this file were not saved.";
    return { ...base, reason };
  }
  const a = Buffer.from(before.data ?? "", "base64"), b = Buffer.from(after.data ?? "", "base64");
  if (a.includes(0) || b.includes(0)) return { ...base, binary: true, diff: "Binary file changed." };
  if (before.hash === after.hash) return base;
  const directory = mkdtempSync(join(tmpdir(), "detach-git-diff-"));
  try {
    writeFileSync(join(directory, "before"), a, { mode: 0o600 });
    writeFileSync(join(directory, "after"), b, { mode: 0o600 });
    const result = await git(directory, ["diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=3", "--", "before", "after"], true, 8 * MAX_FILE_BYTES);
    if (result.code !== 0 && result.code !== 1) throw new Error("Could not compare this file.");
    const lines = result.output.toString().split("\n");
    base.additions = lines.filter(line => line.startsWith("+") && !line.startsWith("+++")).length;
    base.deletions = lines.filter(line => line.startsWith("-") && !line.startsWith("---")).length;
    const hunk = lines.findIndex(line => line.startsWith("@@"));
    const shown = hunk >= 0 ? lines.slice(hunk) : ["File permissions changed."];
    return { ...base, diff: shown.slice(0, 3000).join("\n"),
      ...(shown.length > 3000 ? { reason: "Diff preview is limited to 3,000 lines. Counts include the full file." } : {}) };
  } finally { rmSync(directory, { recursive: true, force: true }); }
}

export async function projectChanges(repo: Repository): Promise<FileChange[]> {
  const raw = (await git(repo.root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])).output.toString().split("\0");
  const files: FileChange[] = [];
  for (let i = 0; i < raw.length && files.length < 200; i++) {
    const entry = raw[i]!; if (!entry) continue;
    const xy = entry.slice(0, 2), path = entry.slice(3);
    const previousPath = xy.includes("R") || xy.includes("C") ? raw[++i] : undefined;
    let change: FileChange;
    if (xy === "??") change = await fileChange(path, missingImage(), captureFile(repo.root, path));
    else {
      try {
        const common = ["--no-ext-diff", "--no-textconv", "--no-color", "--unified=3", "--", ...(previousPath ? [previousPath] : []), path];
        const staged = xy[0] !== " " ? (await git(repo.root, ["diff", "--cached", ...common])).output.toString() : "";
        const unstaged = xy[1] !== " " ? (await git(repo.root, ["diff", ...common])).output.toString() : "";
        const text = [staged ? `Staged changes\n${staged}` : "", unstaged ? `Unstaged changes\n${unstaged}` : ""].filter(Boolean).join("\n");
        const lines = text.split("\n");
        change = { path, status: xy.includes("D") ? "Deleted" : xy.includes("A") ? "Added" : "Modified",
          additions: lines.filter(line => line.startsWith("+") && !line.startsWith("+++")).length,
          deletions: lines.filter(line => line.startsWith("-") && !line.startsWith("---")).length,
          binary: /Binary files .* differ/.test(text), diff: lines.slice(0, 3000).join("\n"),
          ...(lines.length > 3000 ? { reason: "Diff preview is limited to 3,000 lines. Counts include the full file." } : {}) };
      } catch { change = { path, status: "Modified", additions: 0, deletions: 0, binary: false, diff: "", reason: "This file exceeds the diff preview limit or is unavailable." }; }
    }
    files.push({ ...change, previousPath, staged: xy[0] !== " " && xy !== "??", status: previousPath ? "Renamed" : xy === "??" ? "Untracked" : change.status });
  }
  return files;
}
