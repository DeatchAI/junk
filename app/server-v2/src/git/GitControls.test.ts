import { afterEach, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { git, captureFile, repository, snapshot } from "./GitRepository";
import { GitReviewService } from "./GitReviewService";
import { GitStorage } from "./GitStorage";
import { gitResponse } from "../server/GitRoutes";

const directories: string[] = [];
afterEach(() => { for (const directory of directories.splice(0)) rmSync(directory, { recursive: true, force: true }); });
function temporary(prefix: string) { const directory = mkdtempSync(join(tmpdir(), prefix)); directories.push(directory); return directory; }
async function fixture() {
  const root = temporary("detach-git-controls-"), storage = new GitStorage(temporary("detach-git-controls-data-"));
  await git(root, ["init", "-b", "main"]);
  await git(root, ["config", "user.name", "Fixture"]); await git(root, ["config", "user.email", "fixture@example.invalid"]);
  await git(root, ["config", "commit.gpgsign", "false"]);
  writeFileSync(join(root, "file.txt"), "base\n");
  await git(root, ["add", "."]); await git(root, ["commit", "-m", "Base"]);
  return { root, file: join(root, "file.txt"), service: new GitReviewService(storage), storage };
}

test("snapshot budget prioritizes small source files and budget changes do not invent file edits", async () => {
  const { root } = await fixture();
  writeFileSync(join(root, "a-media.bin"), "m".repeat(80));
  writeFileSync(join(root, "z-source.swift"), "let ready = true\n");
  const repo = (await repository(root))!;
  const images = await snapshot(repo, [], 40);
  expect(images["z-source.swift"]!.kind).toBe("file");
  expect(images["a-media.bin"]!.kind).toBe("unsupported");
  expect(images["a-media.bin"]!.reason).toContain("shared 32 MB");
  expect(images["a-media.bin"]!.hash).toBe(captureFile(root, "a-media.bin").hash);
  const preferred = await snapshot(repo, ["a-media.bin"], 80);
  expect(preferred["a-media.bin"]!.kind).toBe("file");
});

test("session revert spans multiple turns, preserves earlier edits/staging, and supports Undo and another revert", async () => {
  const { root, file, service } = await fixture();
  writeFileSync(file, "earlier staged\n"); await git(root, ["add", "file.txt"]);
  writeFileSync(file, "earlier staged\nearlier unstaged\n");
  const original = readFileSync(file), index = readFileSync(join(root, ".git/index"));
  await service.begin(root, "one", "One");
  writeFileSync(file, "earlier staged\nearlier unstaged\nturn one\n");
  writeFileSync(join(root, "new.txt"), "added in chat\n");
  await service.finish("one", "chat");
  await service.begin(root, "two", "Two"); writeFileSync(file, "earlier staged\nearlier unstaged\nturn two\n"); await service.finish("two", "chat");
  const after = readFileSync(file);
  expect((await service.sessionStatus(root, "chat")).canRevert).toBe(true);
  const preview = await service.previewSession(root, "chat");
  await service.apply(preview.id);
  expect(readFileSync(file)).toEqual(original); expect(existsSync(join(root, "new.txt"))).toBe(false);
  expect(readFileSync(join(root, ".git/index"))).toEqual(index);
  expect((await service.sessionReview(root, "chat")).files).toHaveLength(0);
  expect((await service.sessionStatus(root, "chat")).canUndo).toBe(true);
  await service.apply((await service.previewSession(root, "chat", true)).id);
  expect(readFileSync(file)).toEqual(after); expect(existsSync(join(root, "new.txt"))).toBe(true);
  expect((await service.sessionStatus(root, "chat")).canRevert).toBe(true);
  await service.apply((await service.previewSession(root, "chat")).id);
  expect(readFileSync(file)).toEqual(original);
});

test("session revert refuses newer edits, inter-turn edits, staging changes and overlapping runs", async () => {
  const { root, file, service } = await fixture();
  await service.begin(root, "one", "One"); writeFileSync(file, "agent one\n"); await service.finish("one", "chat");
  const preview = await service.previewSession(root, "chat");
  writeFileSync(file, "newer user edit\n");
  expect((await service.sessionStatus(root, "chat")).canRevert).toBe(false);
  await expect(service.apply(preview.id)).rejects.toThrow("changed again");
  await service.begin(root, "two", "Two"); writeFileSync(file, "agent two\n"); await service.finish("two", "chat");
  expect((await service.sessionStatus(root, "chat")).reason).toContain("between");
  await expect(service.previewSession(root, "chat")).rejects.toThrow("between");
  const other = await fixture();
  await other.service.begin(other.root, "a", "A"); await other.service.begin(other.root, "b", "B");
  writeFileSync(other.file, "mixed\n"); await other.service.finish("a", "mixed"); await other.service.finish("b", "other");
  expect((await other.service.sessionStatus(other.root, "mixed")).canRevert).toBe(false);
  const staged = await fixture();
  await staged.service.begin(staged.root, "s", "S"); writeFileSync(staged.file, "agent\n"); await staged.service.finish("s", "staged");
  await git(staged.root, ["add", "file.txt"]);
  expect((await staged.service.sessionStatus(staged.root, "staged")).reason).toContain("staging");
});

test("a new completed turn invalidates an already-open session revert confirmation", async () => {
  const { root, file, service } = await fixture();
  await service.begin(root, "one", "One"); writeFileSync(file, "one\n"); await service.finish("one", "chat");
  const preview = await service.previewSession(root, "chat");
  await service.begin(root, "two", "Two"); writeFileSync(join(root, "another.txt"), "two\n"); await service.finish("two", "chat");
  await expect(service.apply(preview.id)).rejects.toThrow("chat changed");
  expect(readFileSync(file, "utf8")).toBe("one\n");
});

test("session revert cannot write files when its recovery copy is not retained", async () => {
  const { root, file, service, storage } = await fixture();
  await service.begin(root, "one", "One"); writeFileSync(file, "agent change\n"); await service.finish("one", "chat");
  const preview = await service.previewSession(root, "chat");
  storage.saveRecovery = () => {};
  await expect(service.apply(preview.id)).rejects.toThrow("recovery storage limit");
  expect(readFileSync(file, "utf8")).toBe("agent change\n");
});

test("commit includes only chosen current files and preserves unrelated staged files", async () => {
  const { root, file, service } = await fixture();
  writeFileSync(file, "chosen change\n"); writeFileSync(join(root, "new.txt"), "chosen new\n");
  writeFileSync(join(root, "other.txt"), "leave staged\n"); await git(root, ["add", "other.txt"]);
  const plan = await service.previewCommit(root, "project", undefined, ["file.txt", "new.txt"], "main");
  await service.commit(plan.id, "Commit chosen files");
  const names = (await git(root, ["show", "--pretty=", "--name-only", "HEAD"])).output.toString().trim().split("\n").sort();
  expect(names).toEqual(["file.txt", "new.txt"]);
  expect((await git(root, ["diff", "--cached", "--name-only"])).output.toString().trim()).toBe("other.txt");
  expect((await git(root, ["show", "HEAD:file.txt"])).output.toString()).toBe("chosen change\n");
  expect(existsSync(join(root, ".git/index.lock"))).toBe(false);
});

test("committing uses the approved staged contents and leaves later hook edits in the working tree", async () => {
  const { root, file, service } = await fixture();
  writeFileSync(file, "approved contents\n");
  const hook = join(root, ".git/hooks/pre-commit");
  writeFileSync(hook, "#!/bin/sh\nprintf 'later edit\\n' > file.txt\n"); chmodSync(hook, 0o755);
  const plan = await service.previewCommit(root, "project", undefined, ["file.txt"], "main");
  await service.commit(plan.id, "Approved contents");
  expect((await git(root, ["show", "HEAD:file.txt"])).output.toString()).toBe("approved contents\n");
  expect(readFileSync(file, "utf8")).toBe("later edit\n");
});

test("failed commits and changed-after-preview files leave the real staging index untouched", async () => {
  const { root, file, service } = await fixture();
  writeFileSync(file, "chosen\n"); writeFileSync(join(root, "new.txt"), "new\n");
  writeFileSync(join(root, "other.txt"), "staged\n"); await git(root, ["add", "other.txt"]);
  const index = readFileSync(join(root, ".git/index")), head = (await repository(root))!.head;
  const hook = join(root, ".git/hooks/pre-commit"); writeFileSync(hook, "#!/bin/sh\nexit 1\n"); chmodSync(hook, 0o755);
  let plan = await service.previewCommit(root, "project", undefined, ["file.txt", "new.txt"], "main");
  await expect(service.commit(plan.id, "Blocked by hook")).rejects.toThrow();
  expect(readFileSync(join(root, ".git/index"))).toEqual(index); expect((await repository(root))!.head).toBe(head);
  expect(existsSync(join(root, ".git/index.lock"))).toBe(false);
  rmSync(hook);
  plan = await service.previewCommit(root, "project", undefined, ["file.txt"], "main");
  writeFileSync(file, "newer contents\n");
  await expect(service.commit(plan.id, "Stale preview")).rejects.toThrow("changed after");
  expect(readFileSync(join(root, ".git/index"))).toEqual(index);
});

test("push uses a configured remote and never overwrites newer remote commits", async () => {
  const { root, service } = await fixture();
  const remote = temporary("detach-git-remote-");
  await git(remote, ["init", "--bare", "-b", "main"]);
  await git(root, ["remote", "add", "origin", remote]);
  let status = await service.workingStatus(root);
  await service.push(root, { head: status.head, branch: "main", remote: "origin", remoteBranch: "main" });
  expect((await git(remote, ["rev-parse", "refs/heads/main"])).output.toString().trim()).toBe(status.head);
  const peer = temporary("detach-git-peer-");
  await git(peer, ["clone", remote, "."]);
  await git(peer, ["config", "user.name", "Fixture"]); await git(peer, ["config", "user.email", "fixture@example.invalid"]);
  await git(peer, ["config", "commit.gpgsign", "false"]);
  writeFileSync(join(peer, "peer.txt"), "remote update\n"); await git(peer, ["add", "."]); await git(peer, ["commit", "-m", "Remote update"]);
  await git(peer, ["push", "origin", "main"]);
  const remoteHead = (await git(remote, ["rev-parse", "refs/heads/main"])).output.toString().trim();
  status = await service.workingStatus(root);
  await expect(service.push(root, { head: status.head, branch: "main", remote: "origin", remoteBranch: "main" })).rejects.toThrow();
  expect((await git(remote, ["rev-parse", "refs/heads/main"])).output.toString().trim()).toBe(remoteHead);
});

test("Git mutation routes reject browser origins and unexpected commit/push fields", async () => {
  const { root, service } = await fixture();
  for (const route of ["commit-preview", "commit", "push"]) {
    const response = await gitResponse(new Request("http://localhost/api/git/" + route, { method: "POST",
      headers: { origin: "https://example.invalid", "content-type": "application/json" }, body: JSON.stringify({ workspace: root }) }), service);
    expect(response.status).toBe(403);
  }
  const response = await gitResponse(new Request("http://localhost/api/git/push", { method: "POST",
    body: JSON.stringify({ workspace: root, head: "", branch: "main", remote: "origin", remoteBranch: "main", force: true }) }), service);
  expect(response.status).toBe(400);
});
