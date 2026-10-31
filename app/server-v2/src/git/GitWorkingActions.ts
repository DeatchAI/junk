import { chmodSync, closeSync, copyFileSync, existsSync, fsyncSync, lstatSync, mkdtempSync, openSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { git, repository, safeFile, sameRepository } from "./GitRepository";
import type { FileChange, Repository } from "./GitTypes";

interface CommitPlan { id: string; repository: Repository; paths: string[]; hashes: Record<string, string>; createdAt: number }

async function command(repo: Repository, args: string[], indexFile?: string) {
  const result = await git(repo.root, args, true, 4 * 1024 * 1024, { indexFile, timeoutMs: 60_000 });
  if (result.code !== 0) {
    const message = (result.error.toString() || result.output.toString() || "Git could not finish the operation.").trim()
      .replace(/(https?:\/\/)[^\s/@]+(?::[^\s/@]*)?@/g, "$1").slice(0, 1800);
    throw new Error(message);
  }
  return result.output.toString().trim();
}

async function fingerprint(repo: Repository, path: string) {
  const full = safeFile(repo.root, path);
  try {
    const stat = lstatSync(full);
    if (!stat.isFile() || stat.nlink !== 1) throw new Error(path + " is not a regular file and cannot be committed here.");
    return String(stat.mode & 0o777) + ":" + await command(repo, ["hash-object", "--no-filters", "--", path]);
  } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return "missing"; throw error; }
}

function gitOperationInProgress(repo: Repository) {
  return ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer"].some(name => existsSync(join(repo.gitDir, name)));
}

export async function workingStatus(repo: Repository, busy = false) {
  const remotes = (await command(repo, ["remote"])).split("\n").filter(Boolean);
  const upstreamResult = await git(repo.root, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], true);
  const upstream = upstreamResult.code === 0 ? upstreamResult.output.toString().trim() : undefined;
  let ahead = 0, behind = 0;
  if (upstream && repo.head) {
    const counts = await command(repo, ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"]);
    [ahead, behind] = counts.split(/\s+/).map(Number) as [number, number];
  }
  const dirty = (await command(repo, ["status", "--porcelain=v1", "-z", "--untracked-files=all"])).length > 0;
  const branchRemote = (await git(repo.root, ["config", "--get", "branch." + repo.branch + ".remote"], true)).output.toString().trim();
  const merge = (await git(repo.root, ["config", "--get", "branch." + repo.branch + ".merge"], true)).output.toString().trim();
  const operation = gitOperationInProgress(repo);
  const reason = busy ? "Wait for active tasks and Git operations to finish." : operation ? "Finish the current merge or rebase before using these Git controls." : repo.branch === "Detached HEAD" ? "Check out a branch before pushing."
    : !repo.head ? "Create a commit before pushing." : !remotes.length ? "This repository has no Git remote." : behind > 0 ? "The remote branch has newer commits. Pull and review them before pushing." : undefined;
  return { repository: { root: repo.root, branch: repo.branch }, head: repo.head, remotes, upstream, ahead, behind,
    remote: remotes.includes(branchRemote) ? branchRemote : remotes.includes("origin") ? "origin" : remotes[0],
    remoteBranch: merge.startsWith("refs/heads/") ? merge.slice(11) : repo.branch,
    canCommit: !busy && !operation && dirty && repo.branch !== "Detached HEAD", canPush: !reason, pushReason: reason, busy };
}

export class GitWorkingActions {
  private plans = new Map<string, CommitPlan>();

  async preview(repo: Repository, files: FileChange[], requested: string[], branch: string) {
    if (gitOperationInProgress(repo)) throw new Error("Finish the current merge or rebase before committing here.");
    if (repo.branch !== branch || repo.branch === "Detached HEAD") throw new Error("The branch changed. Refresh before committing.");
    const allowed = new Map(files.map(file => [file.path, file]));
    if (!requested.length || requested.length > 200 || requested.some(path => !allowed.has(path))) throw new Error("Choose files from the displayed changes.");
    const paths = [...new Set(requested.flatMap(path => [path, ...(allowed.get(path)?.previousPath ? [allowed.get(path)!.previousPath!] : [])]))].sort();
    const hashes: Record<string, string> = {};
    for (const path of paths) hashes[path] = await fingerprint(repo, path);
    const current = await repository(repo.root);
    if (!current || !sameRepository(current, repo)) throw new Error("Git changed while preparing the commit. Refresh and try again.");
    const plan: CommitPlan = { id: crypto.randomUUID(), repository: repo, paths, hashes, createdAt: Date.now() };
    for (const [id, old] of this.plans) if (Date.now() - old.createdAt > 120_000) this.plans.delete(id);
    this.plans.set(plan.id, plan);
    return { id: plan.id, paths, branch: repo.branch };
  }

  take(id: string) {
    const plan = this.plans.get(id); this.plans.delete(id);
    if (!plan || Date.now() - plan.createdAt > 120_000) throw new Error("The commit preview expired. Review the files again.");
    return plan;
  }

  async commit(repo: Repository, plan: CommitPlan, message: string) {
    if (!message.trim() || message.length > 4000 || message.includes("\0")) throw new Error("Enter a commit message of up to 4,000 characters.");
    if (gitOperationInProgress(repo)) throw new Error("Finish the current merge or rebase before committing here.");
    if (!sameRepository(repo, plan.repository)) throw new Error("The branch, commit, or staging changed. Review the commit again.");
    const indexPath = join(repo.gitDir, "index"), lockPath = indexPath + ".lock";
    let lock: number;
    try { lock = openSync(lockPath, "wx", 0o600); }
    catch { throw new Error("Git staging is in use. Finish the other Git operation and try again."); }
    const lockInode = lstatSync(lockPath).ino;
    let directory: string | undefined, closed = false;
    try {
      const current = await repository(repo.root);
      if (!current || !sameRepository(current, plan.repository)) throw new Error("Git changed after the preview. Review the commit again.");
      for (const path of plan.paths) if (await fingerprint(repo, path) !== plan.hashes[path])
        throw new Error(path + " changed after the commit preview. Review it again.");
      directory = mkdtempSync(join(tmpdir(), "detach-git-commit-"));
      const temporaryIndex = join(directory, "commit-index"), preservedIndex = join(directory, "preserved-index");
      if (existsSync(indexPath)) { copyFileSync(indexPath, preservedIndex); chmodSync(preservedIndex, 0o600); }
      else await command(repo, ["read-tree", "--empty"], preservedIndex);
      await command(repo, ["read-tree", ...(repo.head ? ["HEAD"] : ["--empty"])], temporaryIndex);
      await command(repo, ["add", "-A", "--", ...plan.paths], temporaryIndex);
      for (const path of plan.paths) if (await fingerprint(repo, path) !== plan.hashes[path])
        throw new Error(path + " changed while preparing the commit. Review it again.");
      await command(repo, ["commit", "-m", message.trim()], temporaryIndex);
      // Update only the selected entries of the preserved index. No working files are reset.
      await command(repo, ["reset", "--quiet", "HEAD", "--", ...plan.paths], preservedIndex);
      if (lstatSync(lockPath).ino !== lockInode) throw new Error("Commit created, but another Git client replaced the staging lock. Refresh Git status.");
      writeFileSync(lock, readFileSync(preservedIndex)); fsyncSync(lock); closeSync(lock); closed = true;
      renameSync(lockPath, indexPath);
      const updated = await repository(repo.root);
      return { notice: "Committed " + plan.paths.length + " files.", commit: updated?.head };
    } finally {
      if (!closed) closeSync(lock);
      try { if (lstatSync(lockPath).ino === lockInode) rmSync(lockPath); } catch {}
      if (directory) rmSync(directory, { recursive: true, force: true });
    }
  }

  async push(repo: Repository, input: { head: string; branch: string; remote: string; remoteBranch: string }) {
    const status = await workingStatus(repo);
    if (!status.canPush) throw new Error(status.pushReason);
    if (repo.head !== input.head || repo.branch !== input.branch) throw new Error("The branch changed. Review the push destination again.");
    if (!status.remotes.includes(input.remote) || input.remoteBranch !== status.remoteBranch)
      throw new Error("The push destination changed. Review it again.");
    const expectedRef = "refs/heads/" + input.remoteBranch;
    await command(repo, ["push", ...(status.upstream ? [] : ["--set-upstream"]), "--porcelain", "--",
      input.remote, "refs/heads/" + repo.branch + ":" + expectedRef]);
    return { notice: "Pushed " + repo.branch + " to " + input.remote + "/" + input.remoteBranch + "." };
  }
}
