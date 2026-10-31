import { applyRestore } from "./GitRestoration";
import { matchingImages, sameRepository } from "./GitRepository";
import { sessionImages } from "./GitSessionReview";
import type { GitStorage } from "./GitStorage";
import { imageAt, type FileImage, type Repository, type RecoveryRecord, type RestorePlan } from "./GitTypes";

export function loadSession(storage: GitStorage, root: string, conversationID: string) {
  const tasks = storage.tasks().filter(task => task.repository.root === root && task.conversationID === conversationID)
    .flatMap(header => { const task = storage.task(header.runId); return task ? [task] : []; });
  const ids = new Set(tasks.map(task => task.runId));
  const recoveries = storage.recoveries().filter(record => record.repository.root === root &&
    (record.conversationID === conversationID || ids.has(record.runId)))
    .flatMap(header => { const record = storage.recovery(header.id); return record ? [record] : []; });
  return { tasks, recoveries, images: sessionImages(tasks, recoveries) };
}

export function sessionSafety(storage: GitStorage, repo: Repository, conversationID: string, busy: boolean) {
  const { tasks, recoveries, images } = loadSession(storage, repo.root, conversationID);
  const recovery = recoveries.filter(record => record.conversationID === conversationID && !record.undone)
    .sort((a, b) => b.createdAt - a.createdAt)[0];
  let reason: string | undefined;
  if (busy) reason = "Wait for active tasks and Git operations to finish.";
  else if (!tasks.length) reason = "This chat has no saved starting snapshot.";
  else if (tasks.some(task => task.notice)) reason = "Some turns have no complete starting snapshot.";
  else if (tasks.some(task => task.mixed)) reason = "Tasks overlapped in this project, so these changes cannot be isolated safely.";
  else if (!images.coherent) reason = "Files were edited between this chat's turns. Those edits cannot be separated safely.";
  else if (tasks.some(task => !sameRepository(task.repository, repo))) reason = "The branch, commits, or Git staging changed after the snapshot.";
  else if (images.paths.some(path => images.before[path]!.kind === "unsupported" || images.after[path]!.kind === "unsupported"))
    reason = "Some changed files have no complete snapshot and cannot be reverted safely.";
  else if (!images.paths.length) reason = "There are no session changes to revert.";
  else if ([...Object.values(images.before), ...Object.values(images.after)].reduce((size, image) => size + (image.data?.length ?? 0) + 512, 0) > 120 * 1024 * 1024)
    reason = "This session exceeds the recovery storage limit. Revert one task at a time.";
  else {
    try { matchingImages(repo.root, images.after, images.paths); }
    catch { reason = "Files changed again after this chat. Newer edits will be kept."; }
  }
  let canUndo = false;
  if (recovery && !busy && sameRepository(recovery.repository, repo)) {
    try { matchingImages(repo.root, recovery.after, recovery.remainingPaths ?? Object.keys(recovery.after)); canUndo = true; } catch {}
  }
  return { repository: { root: repo.root, branch: repo.branch }, hasChanges: images.paths.length > 0,
    canRevert: !reason, canUndo, reason, recoveryID: recovery?.id, runID: tasks.sort((a,b) => b.completedAt-a.completedAt)[0]?.runId };
}

export function previewSession(storage: GitStorage, repo: Repository, conversationID: string, busy: boolean, undo: boolean): RestorePlan {
  const safety = sessionSafety(storage, repo, conversationID, busy);
  if (undo ? !safety.canUndo : !safety.canRevert) throw new Error(undo ? "These reverted files changed again or recovery is unavailable." : safety.reason);
  const { tasks, images } = loadSession(storage, repo.root, conversationID);
  const recovery = undo && safety.recoveryID ? storage.recovery(safety.recoveryID) : undefined;
  const pick = (source: Record<string, FileImage>) => Object.fromEntries((recovery?.remainingPaths ?? Object.keys(source)).map(path => [path, source[path]!]));
  const from = recovery ? pick(recovery.after) : images.after, to = recovery ? pick(recovery.before) : images.before;
  return { id: crypto.randomUUID(), runId: "session:" + conversationID, conversationID,
    sessionRunIDs: tasks.map(task => task.runId).sort(), action: undo ? "undo" : "discard",
    recoveryID: recovery?.id, paths: Object.keys(from).sort(), createdAt: Date.now(), repository: repo, from, to };
}

export function applySession(storage: GitStorage, plan: RestorePlan) {
  const current = loadSession(storage, plan.repository.root, plan.conversationID!);
  if (JSON.stringify(current.tasks.map(task => task.runId).sort()) !== JSON.stringify(plan.sessionRunIDs))
    throw new Error("This chat changed after the preview. Review its changes again.");
  const pick = (source: Record<string, FileImage>, paths: string[]) => Object.fromEntries(paths.map(path => [path, imageAt(source, path)]));
  const recovery: RecoveryRecord = { id: crypto.randomUUID(), runId: plan.runId, conversationID: plan.conversationID,
    createdAt: Date.now(), repository: plan.repository, before: pick(plan.from, plan.paths), after: pick(plan.to, plan.paths), undone: plan.action === "undo" };
  storage.saveRecovery(recovery);
  if (!storage.recovery(recovery.id)) throw new Error("The recovery storage limit was reached. No files were changed.");
  const result = applyRestore(plan);
  recovery.before = pick(plan.from, result.applied); recovery.after = pick(plan.to, result.applied);
  if (!result.applied.length) recovery.undone = true;
  storage.saveRecovery(recovery);
  if (plan.action === "undo" && plan.recoveryID) {
    const original = storage.recovery(plan.recoveryID);
    if (original) {
      original.remainingPaths = (original.remainingPaths ?? Object.keys(original.after)).filter(path => !result.applied.includes(path));
      original.undone = !original.remainingPaths.length;
      storage.saveRecovery(original);
    }
  }
  return { ...result, notice: result.failures.length ? "Some files were kept unchanged. " + result.failures.join(" ")
    : plan.action === "undo" ? "Session revert undone." : "Session changes reverted. Undo is available." };
}
