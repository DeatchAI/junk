import { afterEach, describe, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, statSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { git, MAX_FILE_BYTES, repository } from "./GitRepository";
import { GitReviewService } from "./GitReviewService";
import { GitStorage } from "./GitStorage";
import { gitResponse } from "../server/GitRoutes";

const directories: string[] = [];
afterEach(() => { for (const dir of directories.splice(0)) rmSync(dir, { recursive: true, force: true }); });
async function fixture() {
  const root = mkdtempSync(join(tmpdir(), "detach-git-test-")); directories.push(root);
  await git(root, ["init", "-b", "main"]);
  await git(root, ["config", "user.name", "Fixture"]); await git(root, ["config", "user.email", "fixture@example.invalid"]);
  writeFileSync(join(root, "file.txt"), "first\nsecond\n");
  writeFileSync(join(root, ".gitignore"), "ignored/\n");
  await git(root, ["add", "."]); await git(root, ["commit", "-m", "Fixture"]);
  const data = mkdtempSync(join(tmpdir(), "detach-git-data-")); directories.push(data);
  const storage = new GitStorage(data), service = new GitReviewService(storage);
  return { root, data, storage, service, file: join(root, "file.txt") };
}

describe("local Git review and restoration", () => {
  test("chat review merges its turns and excludes earlier edits and other conversations", async () => {
    const { root, file, service } = await fixture();
    writeFileSync(file, "user edit before chat\n");
    await service.begin(root, "chat-first", "First");
    writeFileSync(file, "first turn\n");
    await service.finish("chat-first", "chat-a", 0);
    await service.begin(root, "unrelated", "Other chat");
    writeFileSync(join(root, "other.txt"), "other conversation\n");
    await service.finish("unrelated", "chat-b", 0);
    await service.begin(root, "chat-second", "Second");
    writeFileSync(file, "second turn\n");
    writeFileSync(join(root, "added.txt"), "new in chat\n");
    await service.finish("chat-second", "chat-a", 1);
    const review = await service.sessionReview(root, "chat-a");
    expect(review.files.map(file => file.path)).toEqual(["added.txt", "file.txt"]);
    const diff = review.files.find(file => file.path === "file.txt")!.diff;
    expect(diff).toContain("-user edit before chat"); expect(diff).toContain("+second turn");
    expect(diff).not.toContain("first turn"); expect(review.canDiscard).toBe(false);
    const response = await gitResponse(new Request(`http://localhost/api/git/review?workspace=${encodeURIComponent(root)}&scope=session&conversation=chat-a`), service);
    expect((await response.json() as { files: unknown[] }).files).toHaveLength(2);
    expect((await service.sessionReview(root, "missing")).files).toEqual([]);
  });

  test("chat review omits reverted and discarded changes and restores them after Undo", async () => {
    const { root, file, service } = await fixture();
    const before = readFileSync(file, "utf8");
    await service.begin(root, "first", "Edit"); writeFileSync(file, "changed\n"); await service.finish("first", "chat", 0);
    await service.begin(root, "second", "Revert"); writeFileSync(file, before); await service.finish("second", "chat", 1);
    expect((await service.sessionReview(root, "chat")).files).toEqual([]);
    await service.begin(root, "third", "Add"); writeFileSync(file, "new change\n"); await service.finish("third", "chat", 2);
    await service.apply((await service.preview(root, "third")).id);
    expect((await service.sessionReview(root, "chat")).files).toEqual([]);
    await service.apply((await service.preview(root, "third", undefined, true)).id);
    expect((await service.sessionReview(root, "chat")).files).toHaveLength(1);
  });

  test("preserves earlier staged and unstaged edits, persists the task, and recovers a discard", async () => {
    const { root, file, service, storage, data } = await fixture();
    writeFileSync(file, "staged user edit\n"); await git(root, ["add", "file.txt"]);
    writeFileSync(file, "staged user edit\nunstaged user edit\n");
    const before = readFileSync(file), index = readFileSync(join(root, ".git/index"));
    await service.begin(root, "run-1", "Improve this file");
    writeFileSync(file, Buffer.concat([before, Buffer.from("task edit\n")]));
    await service.finish("run-1", "native-chat");
    const view = await service.review(root, "run-1");
    expect(view.files).toHaveLength(1); expect(view.files[0]!.additions).toBe(1); expect(view.canDiscard).toBe(true);
    expect((await service.tasks(root, "native-chat"))[0]!.promptHash).toHaveLength(64);
    const after = readFileSync(file);
    const preview = await service.preview(root, "run-1", ["file.txt"]);
    await service.apply(preview.id);
    expect(readFileSync(file)).toEqual(before); expect(readFileSync(join(root, ".git/index"))).toEqual(index);
    expect(storage.status().recoveryCount).toBe(1);
    const reopened = new GitReviewService(new GitStorage(data));
    expect((await reopened.review(root, "run-1")).files[0]!.discarded).toBe(true);
    await reopened.apply((await reopened.preview(root, "run-1", undefined, true)).id);
    expect(readFileSync(file)).toEqual(after); expect(readFileSync(join(root, ".git/index"))).toEqual(index);
    expect(statSync(data).mode & 0o777).toBe(0o700);
  });

  test("refuses changed-again files between confirmation and apply, including Undo", async () => {
    const { root, file, service, storage } = await fixture();
    await service.begin(root, "run", "Edit"); writeFileSync(file, "task\n"); await service.finish("run", "chat");
    const plan = await service.preview(root, "run"); writeFileSync(file, "newer user edit\n");
    await expect(service.apply(plan.id)).rejects.toThrow("changed again");
    expect(readFileSync(file, "utf8")).toBe("newer user edit\n"); expect(storage.status().recoveryCount).toBe(0);
    writeFileSync(file, "task\n"); await service.apply((await service.preview(root, "run")).id);
    writeFileSync(file, "after discard edit\n");
    await expect(service.preview(root, "run", undefined, true)).rejects.toThrow("changed again");
  });

  test("restores added, deleted and renamed files without resetting the index", async () => {
    const { root, file, service } = await fixture();
    await service.begin(root, "run", "Rename and add");
    renameSync(file, join(root, "renamed.txt")); writeFileSync(join(root, "new file.txt"), "new\n");
    await service.finish("run", "chat");
    const view = await service.review(root, "run");
    expect(view.files.find(file => file.path === "renamed.txt")?.status).toBe("Renamed");
    await service.apply((await service.preview(root, "run", ["renamed.txt"])).id);
    expect(existsSync(file)).toBe(true); expect(existsSync(join(root, "renamed.txt"))).toBe(false);
    expect(existsSync(join(root, "new file.txt"))).toBe(true);
    await service.apply((await service.preview(root, "run", ["new file.txt"])).id);
    expect(existsSync(join(root, "new file.txt"))).toBe(false);
  });

  test("overlapping Detach runs disable automatic task discard", async () => {
    const { root, file, service } = await fixture();
    await service.begin(root, "one", "One"); await service.begin(root, "two", "Two");
    writeFileSync(file, "overlapping\n"); await service.finish("one", "chat");
    expect((await service.review(root, "one")).canDiscard).toBe(false);
    await service.finish("two", "chat");
    await expect(service.preview(root, "one")).rejects.toThrow("Mixed changes");
    await expect(service.preview(root, "two")).rejects.toThrow("Mixed changes");
  });

  test("staging or commit changes after the task invalidate restoration", async () => {
    const { root, file, service } = await fixture();
    await service.begin(root, "run", "Edit"); writeFileSync(file, "task\n"); await service.finish("run", "chat");
    const plan = await service.preview(root, "run"); await git(root, ["add", "file.txt"]);
    await expect(service.apply(plan.id)).rejects.toThrow("staging state changed");
    expect(readFileSync(file, "utf8")).toBe("task\n");
  });

  test("symlinks, parent symlinks and oversized files are never overwritten", async () => {
    const { root, file, service } = await fixture();
    const external = join(directories[directories.length - 1]!, "outside"); writeFileSync(external, "outside");
    await service.begin(root, "run", "Edit"); unlinkSync(file); symlinkSync(external, file);
    writeFileSync(join(root, "large.bin"), Buffer.alloc(MAX_FILE_BYTES + 1));
    await service.finish("run", "chat");
    await expect(service.preview(root, "run", ["file.txt"])).rejects.toThrow("cannot be safely restored");
    await expect(service.preview(root, "run", ["large.bin"])).rejects.toThrow("cannot be safely restored");
    expect(readFileSync(external, "utf8")).toBe("outside");
    await expect(service.preview(root, "run", ["../outside"])).rejects.toThrow("current task");
  });

  test("binary and executable-mode changes are accurately reviewable and recoverable", async () => {
    const { root, file, service } = await fixture();
    await service.begin(root, "run", "Binary"); writeFileSync(file, Buffer.from([0, 1, 2, 3])); chmodSync(file, 0o755);
    await service.finish("run", "chat");
    expect((await service.review(root, "run")).files[0]!.binary).toBe(true);
    await service.apply((await service.preview(root, "run")).id);
    expect(readFileSync(file, "utf8")).toBe("first\nsecond\n"); expect(statSync(file).mode & 0o777).toBe(0o644);
  });

  test("project review separates staged/untracked files and imports have no invented task baseline", async () => {
    const { root, file, service } = await fixture();
    writeFileSync(file, "earlier\n"); await git(root, ["add", "file.txt"]);
    writeFileSync(join(root, "new.txt"), "new\n");
    const view = await service.review(root);
    expect(view.canDiscard).toBe(false); expect(view.notice).toContain("Task comparison unavailable");
    expect(view.files.find(f => f.path === "file.txt")?.staged).toBe(true);
    expect(view.files.find(f => f.path === "new.txt")?.status).toBe("Untracked");
  });

  test("privacy settings clear snapshots and recovery without touching project files", async () => {
    const { root, file, service } = await fixture();
    await service.begin(root, "run", "Edit"); writeFileSync(file, "task\n");
    expect(() => service.settings(false)).toThrow("Finish active tasks");
    await service.finish("run", "chat"); service.settings(false);
    expect(service.settings()).toMatchObject({ enabled: false, taskCount: 0, recoveryCount: 0 });
    expect(readFileSync(file, "utf8")).toBe("task\n");
  });

  test("project diffs retain both staging and newer working-tree changes", async () => {
    const { root, file, service } = await fixture();
    writeFileSync(file, "staged replacement\n"); await git(root, ["add", "file.txt"]);
    writeFileSync(file, "first\nsecond\n");
    const change = (await service.review(root)).files.find(f => f.path === "file.txt")!;
    expect(change.diff).toContain("Staged changes"); expect(change.diff).toContain("Unstaged changes");
    expect(change.diff).toContain("+staged replacement"); expect(change.diff).toContain("-staged replacement");
    writeFileSync(join(root, "added.txt"), "staged new file\n"); await git(root, ["add", "added.txt"]);
    const added = (await service.review(root)).files.find(f => f.path === "added.txt")!;
    expect(added.status).toBe("Added"); expect(added.additions).toBe(1);
  });

  test("worktrees use their own root and index; ignored files stay out of snapshots", async () => {
    const { root, service } = await fixture();
    const worktree = mkdtempSync(join(tmpdir(), "detach-linked-worktree-")); directories.push(worktree);
    await git(root, ["worktree", "add", "-b", "other", worktree]);
    mkdirSync(join(worktree, "ignored")); writeFileSync(join(worktree, "ignored", "private.txt"), "private");
    await service.begin(worktree, "linked", "Edit linked tree");
    writeFileSync(join(worktree, "file.txt"), "linked edit\n"); writeFileSync(join(worktree, "ignored", "private.txt"), "new private");
    await service.finish("linked", "linked-chat");
    const view = await service.review(worktree, "linked");
    expect(view.repository?.branch).toBe("other"); expect(view.files).toHaveLength(1);
    await service.apply((await service.preview(worktree, "linked")).id);
    expect(readFileSync(join(root, "file.txt"), "utf8")).toBe("first\nsecond\n");
    expect(readFileSync(join(worktree, "ignored", "private.txt"), "utf8")).toBe("new private");
  });

  test("non-repositories remain untouched", async () => {
    const root = mkdtempSync(join(tmpdir(), "detach-no-git-")); directories.push(root);
    expect(await repository(root)).toBeUndefined(); expect(existsSync(join(root, ".git"))).toBe(false);
  });

  test("Git endpoints reject browser origins, unexpected mutations and reused plans", async () => {
    const { root, file, service } = await fixture();
    const request = (route: string, body?: unknown, headers?: Record<string, string>) => new Request(`http://127.0.0.1/api/git/${route}`, {
      method: body ? "POST" : "GET", body: body ? JSON.stringify(body) : undefined, headers });
    expect((await gitResponse(request("settings", undefined, { Origin: "https://example.invalid" }), service)).status).toBe(403);
    expect((await gitResponse(request("apply", { command: "reset --hard" }), service)).status).toBe(400);
    expect((await gitResponse(request("settings", { enabled: "false" }), service)).status).toBe(400);
    await service.begin(root, "run", "Edit"); writeFileSync(file, "task\n"); await service.finish("run", "chat");
    const plan = await service.preview(root, "run"); await service.apply(plan.id);
    await expect(service.apply(plan.id)).rejects.toThrow("expired");
    expect((await gitResponse(request("settings"), service)).headers.get("cache-control")).toBe("no-store");
  });
});
