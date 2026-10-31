import { chmodSync, lstatSync, mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { captureFile, matchingImages, safeFile } from "./GitRepository";
import { imageAt, type FileImage, type RestorePlan } from "./GitTypes";

function writeImage(root: string, path: string, image: FileImage) {
  if (image.kind === "unsupported") throw new Error("This file cannot be safely restored.");
  const full = safeFile(root, path);
  if (image.kind === "missing") { rmSync(full, { force: true }); return; }
  mkdirSync(dirname(full), { recursive: true });
  safeFile(root, path);
  const temporary = join(dirname(full), `.${basename(full)}.detach-${crypto.randomUUID()}`);
  try {
    writeFileSync(temporary, Buffer.from(image.data!, "base64"), { flag: "wx", mode: image.mode });
    chmodSync(temporary, image.mode ?? 0o644);
    // Never replace a symlink/directory that appeared after validation.
    try { if (!lstatSync(full).isFile()) throw new Error("This file changed again. Refresh before restoring."); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    safeFile(root, path);
    renameSync(temporary, full);
  } finally { rmSync(temporary, { force: true }); }
}

/** A recovery record is persisted by the caller before the first write. */
export function applyRestore(plan: RestorePlan) {
  const applied: string[] = [], failures: string[] = [];
  for (const path of plan.paths) {
    try {
      matchingImages(plan.repository.root, plan.from, [path]);
      writeImage(plan.repository.root, path, imageAt(plan.to, path));
      if (captureFile(plan.repository.root, path).hash !== imageAt(plan.to, path).hash) throw new Error("Could not verify the restored contents.");
      applied.push(path);
    } catch (error) { failures.push(`${path}: ${error instanceof Error ? error.message : "Restore failed."}`); }
  }
  return { applied, failures };
}
