import { createHash } from "node:crypto";
import { constants, closeSync, fstatSync, lstatSync, openSync, readFileSync, realpathSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { processEnv } from "../runtime/ProcessRunner";
import { imageAt, missingImage, type FileImage, type Repository } from "./GitTypes";

export const MAX_FILE_BYTES = 2 * 1024 * 1024;
export const MAX_SNAPSHOT_BYTES = 32 * 1024 * 1024;
export const digest = (data: string | Buffer) => createHash("sha256").update(data).digest("hex");

export async function git(root: string, args: string[], acceptFailure = false, limit = 4 * 1024 * 1024, options: { indexFile?: string; timeoutMs?: number } = {}) {
  const env = processEnv();
  for (const name of Object.keys(env)) if (name.startsWith("GIT_")) delete env[name];
  Object.assign(env, { GIT_OPTIONAL_LOCKS: "0", GIT_TERMINAL_PROMPT: "0", LC_ALL: "C" });
  if (options.indexFile) env.GIT_INDEX_FILE = options.indexFile;
  const child = Bun.spawn(["git", "--no-pager", "--literal-pathspecs", "-c", "core.fsmonitor=false", "-C", root, ...args],
    { env, stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  const timer = setTimeout(() => child.kill(), options.timeoutMs ?? 10_000);
  async function read(stream: ReadableStream<Uint8Array>) {
    const chunks: Buffer[] = []; let bytes = 0;
    for await (const chunk of stream) {
      bytes += chunk.byteLength;
      if (bytes > limit) { child.kill(); throw new Error("This Git response exceeds the review size limit."); }
      chunks.push(Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
  }
  try {
    const [code, output, error] = await Promise.all([child.exited, read(child.stdout), read(child.stderr)]);
    if (code !== 0 && !acceptFailure) throw new Error("Git could not read this repository. Refresh and try again.");
    return { code, output, error };
  } finally { clearTimeout(timer); }
}

export async function repository(workspace: string): Promise<Repository | undefined> {
  if (!isAbsolute(workspace) || workspace.includes("\0")) throw new Error("Choose an absolute project folder.");
  const result = await git(workspace, ["rev-parse", "--show-toplevel"], true);
  if (result.code !== 0) return undefined;
  const root = realpathSync(result.output.toString().trim());
  const gitDir = realpathSync((await git(root, ["rev-parse", "--absolute-git-dir"])).output.toString().trim());
  const head = (await git(root, ["rev-parse", "--verify", "HEAD"], true)).output.toString().trim();
  const branch = (await git(root, ["symbolic-ref", "--quiet", "--short", "HEAD"], true)).output.toString().trim() || "Detached HEAD";
  let indexHash = "missing";
  try { indexHash = digest(readFileSync(join(gitDir, "index"))); } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  return { root, gitDir, head, branch, indexHash };
}

export function safeFile(root: string, path: string) {
  if (!path || path.includes("\0") || isAbsolute(path) || path.split(/[\\/]/).some(p => p === ".git" || p === "..")) {
    throw new Error("This path is outside the reviewable working tree.");
  }
  const full = resolve(root, path), rel = relative(root, full);
  if (!rel || rel.startsWith(".." + sep) || isAbsolute(rel)) throw new Error("This path is outside the repository.");
  const parts = rel.split(sep); let parent = root;
  for (const part of parts.slice(0, -1)) {
    parent = join(parent, part);
    try { if (!lstatSync(parent).isDirectory()) throw new Error("A parent folder is a symbolic link or is unavailable."); }
    catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") break; throw error; }
  }
  return full;
}

export function captureFile(root: string, path: string, allowance = MAX_FILE_BYTES): FileImage {
  let fd: number | undefined;
  try {
    const full = safeFile(root, path), stat = lstatSync(full);
    const unsupported = (reason: string): FileImage => ({ kind: "unsupported", size: stat.size,
      hash: digest(`${stat.mode}:${stat.size}:${stat.mtimeMs}:${stat.ctimeMs}`), reason });
    if (!stat.isFile() || stat.nlink !== 1) return unsupported("Symbolic links, hard links and submodules are review-only.");
    if (stat.size > MAX_FILE_BYTES) return unsupported("This file is larger than the 2 MB text snapshot limit.");
    fd = openSync(full, constants.O_RDONLY | constants.O_NOFOLLOW);
    const opened = fstatSync(fd);
    if (opened.ino !== stat.ino || opened.size !== stat.size) throw new Error("This file changed while being read.");
    const bytes = readFileSync(fd);
    if (bytes.length > MAX_FILE_BYTES) return unsupported("This file is larger than the 2 MB text snapshot limit.");
    const mode = stat.mode & 0o777;
    const hash = digest(Buffer.concat([Buffer.from(`${mode}:`), bytes]));
    if (bytes.length > allowance) return { kind: "unsupported", hash, mode, size: bytes.length,
      reason: "The shared 32 MB session snapshot budget was exhausted before this file could be saved." };
    return { kind: "file", data: bytes.toString("base64"), hash, mode, size: bytes.length };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return missingImage();
    return { kind: "unsupported", hash: "unavailable", size: 0, reason: error instanceof Error ? error.message : "File unavailable." };
  } finally { if (fd !== undefined) closeSync(fd); }
}

export async function snapshot(repo: Repository, preferred: string[] = [], budget = MAX_SNAPSHOT_BYTES) {
  const tracked = (await git(repo.root, ["ls-files", "-z"])).output.toString().split("\0");
  const untracked = (await git(repo.root, ["ls-files", "--others", "--exclude-standard", "-z"])).output.toString().split("\0");
  const paths = [...new Set([...tracked, ...untracked].filter(Boolean))];
  if (paths.length > 10_000) throw new Error("This project exceeds the 10,000-file task snapshot limit. Project review is still available.");
  const preferredSet = new Set(preferred);
  const source = /\.(swift|[cm]?[jt]sx?|md|txt|json|ya?ml|toml|css|scss|html|xml|sh|py|rb|rs|go|[ch](pp)?)$/i;
  const ranked = paths.map(path => {
    let size = Number.MAX_SAFE_INTEGER;
    try { size = lstatSync(safeFile(repo.root, path)).size; } catch {}
    return { path, size, rank: preferredSet.has(path) ? -1 : source.test(path) ? 0 : 1 };
  }).sort((a, b) => a.rank - b.rank || a.size - b.size || a.path.localeCompare(b.path));
  let remaining = budget;
  const images: Record<string, FileImage> = Object.create(null);
  for (const { path } of ranked) {
    const image = captureFile(repo.root, path, Math.max(0, remaining));
    images[path] = image; if (image.kind === "file") remaining -= image.size;
  }
  return images;
}

export const sameRepository = (a: Repository, b: Repository) => a.root === b.root && a.gitDir === b.gitDir && a.head === b.head && a.indexHash === b.indexHash;
export function matchingImages(root: string, images: Record<string, FileImage>, paths: string[]) {
  for (const path of paths) {
    const expected = imageAt(images, path), actual = captureFile(root, path);
    if (actual.kind === "unsupported" || expected.kind === "unsupported" || actual.hash !== expected.hash) {
      throw new Error(`${path} changed again or cannot be safely restored. Refresh to review its latest changes.`);
    }
  }
}
