import { promptFingerprint } from "../branches/BranchTypes";
import { fileChange, projectChanges } from "./GitDiff";
import { captureFile, matchingImages, repository, sameRepository, snapshot } from "./GitRepository";
import { applyRestore } from "./GitRestoration";
import { GitStorage } from "./GitStorage";
import { sessionChanges } from "./GitSessionReview";
import { loadSession, sessionSafety, previewSession, applySession } from "./GitSessionRestore";
import { GitWorkingActions, workingStatus } from "./GitWorkingActions";
import type { Repository } from "./GitTypes";
import { imageAt, type FileImage, type RecoveryRecord, type RestorePlan, type TaskRecord } from "./GitTypes";

export class GitReviewService {
  private active = new Map<string, TaskRecord>();
  private restoring = new Set<string>();
  private plans = new Map<string, RestorePlan>();
  private working = new GitWorkingActions();
  constructor(readonly storage = new GitStorage()) {}

  async begin(workspace: string, runId: string, prompt: string) {
    const repo = await repository(workspace).catch(() => undefined);
    if (!repo) return;
    if (this.restoring.has(repo.root)) throw new Error("Project files are being restored. Try this task again when restoration finishes.");
    const task: TaskRecord = { runId, promptHash: promptFingerprint(prompt), startedAt: Date.now(), completedAt: 0,
      repository: repo, mixed: false, before: Object.create(null), after: Object.create(null), files: [] };
    for (const other of this.active.values()) if (other.repository.root === repo.root) { other.mixed = true; task.mixed = true; }
    this.active.set(runId, task);
    if (!this.storage.enabled) { task.notice = "Task snapshots are turned off. Project changes are still available."; return; }
    try { task.before = await snapshot(repo); }
    catch (error) { task.notice = error instanceof Error ? error.message : "The starting snapshot could not be captured."; }
  }

  async finish(runId: string, conversationID?: string, messageOrdinal?: number) {
    const task = this.active.get(runId); if (!task) return;
    try {
      task.conversationID = conversationID; task.messageOrdinal = messageOrdinal; task.completedAt = Date.now();
      if (!this.storage.enabled) return;
      if (!task.notice) {
        const after = await snapshot(task.repository, Object.keys(task.before).filter(path => task.before[path]!.kind === "file"));
        const before: Record<string, FileImage> = Object.create(null), changedAfter: Record<string, FileImage> = Object.create(null);
        for (const path of new Set([...Object.keys(task.before), ...Object.keys(after)])) {
          const a = imageAt(task.before, path), b = imageAt(after, path);
          if (a.hash === b.hash) continue;
          before[path] = a; changedAfter[path] = b;
          task.files.push(await fileChange(path, a, b));
        }
        task.before = before; task.after = changedAfter;
        // Pair exact-content renames; edited renames remain explicit add/delete entries.
        for (const added of [...task.files].filter(file => file.status === "Added")) {
          const removed = task.files.find(file => file.status === "Deleted" && imageAt(before, file.path).hash === imageAt(changedAfter, added.path).hash);
          if (!removed) continue;
          const comparison = await fileChange(added.path, imageAt(before, removed.path), imageAt(changedAfter, added.path));
          Object.assign(added, comparison, { status: "Renamed", previousPath: removed.path,
            diff: `Renamed from ${removed.path}\n${comparison.diff}` });
          task.files = task.files.filter(file => file !== removed);
        }
      }
      this.storage.saveTask(task);
    } catch (error) {
      task.before = {}; task.after = {}; task.files = [];
      task.notice = error instanceof Error ? error.message : "The completed changes could not be captured.";
      this.storage.saveTask(task);
    } finally { this.active.delete(runId); }
  }

  async tasks(workspace: string, conversationID?: string) {
    const repo = await repository(workspace);
    return repo ? this.storage.tasks().filter(task => task.repository.root === repo.root && (!conversationID || task.conversationID === conversationID))
      .sort((a, b) => b.startedAt - a.startedAt).map(task => this.summary(task)) : [];
  }
  summary(task: TaskRecord) {
    return { runId: task.runId, conversationID: task.conversationID, messageOrdinal: task.messageOrdinal, promptHash: task.promptHash, startedAt: task.startedAt,
      completedAt: task.completedAt, repository: task.repository, mixed: task.mixed, notice: task.notice,
      files: task.files.map(({ diff, ...file }) => file), recoveryID: this.latestRecovery(task.runId)?.id };
  }

  async sessionReview(workspace: string, conversationID: string) {
    const repo = await repository(workspace);
    if (!repo) return { repository: null, files: [], canDiscard: false, notice: "Change review requires a Git repository." };
    const { tasks, recoveries } = loadSession(this.storage, repo.root, conversationID);
    const latest = tasks.sort((a, b) => b.startedAt - a.startedAt || b.completedAt - a.completedAt)[0];
    return { repository: repo, files: await sessionChanges(tasks, recoveries), canDiscard: false, recoveryID: sessionSafety(this.storage, repo, conversationID, this.busy(repo.root)).recoveryID, task: latest ? this.summary(latest) : undefined,
      notice: tasks.some(task => task.notice) ? "Some tasks have no saved snapshot. Only captured changes are shown." : undefined };
  }

  async review(workspace: string, runId?: string, project = false) {
    const repo = await repository(workspace);
    if (!repo) return { repository: null, files: [], notice: "Change review requires a Git repository.", canDiscard: false };
    const task = runId ? this.storage.task(runId) : undefined;
    if (task && task.repository.root !== repo.root) throw new Error("This task belongs to another project.");
    const active = [...this.active.values()].some(value => value.repository.root === repo.root);
    const reason = active ? "Another task is running in this repository. Discard is available when all tasks finish."
      : task?.mixed ? "Mixed changes: tasks overlapped in this project. Review is available; automatic task discard is unavailable."
      : task && !sameRepository(task.repository, repo) ? "The Git branch or staging state changed. Automatic task discard is unavailable."
      : task?.notice;
    const files = project || !task ? await projectChanges(repo) : task.files;
    return { repository: repo, files: files.map(file => ({ ...file, earlier: project && !!task && !task.files.some(f => f.path === file.path) })),
      task: task ? this.summary(task) : undefined, canDiscard: !!task && !project && !reason && !this.restoring.has(repo.root),
      notice: reason ?? (!task && !project ? "Task comparison unavailable for this session. Showing current project changes."
        : files.length >= 200 && project ? "Showing the first 200 changed files in this project." : undefined),
      recoveryID: task ? this.latestRecovery(task.runId)?.id : undefined };
  }

  async preview(workspace: string, runId: string, paths?: string[], undo = false) {
    const task = this.storage.task(runId); if (!task) throw new Error("This task snapshot is unavailable or has expired.");
    const view = await this.review(workspace, runId);
    const repo = view.repository!;
    if (!view.canDiscard) throw new Error(view.notice || "File restoration is temporarily unavailable.");
    const recoveryHeader = undo ? this.latestRecovery(runId) : undefined;
    const recovery = recoveryHeader ? this.storage.recovery(recoveryHeader.id) : undefined;
    if (undo && !recovery) throw new Error("No discard recovery is available for this task.");
    const from = recovery?.after ?? task.after, to = recovery?.before ?? task.before;
    const available = Object.keys(from).filter(path => undo ? (recovery?.remainingPaths ?? Object.keys(from)).includes(path) : !task.files.find(f => f.path === path || f.previousPath === path)?.discarded);
    const selected = paths ? [...new Set(paths.flatMap(path => {
      const file = task.files.find(file => file.path === path);
      return file?.previousPath ? [path, file.previousPath] : [path];
    }))] : available;
    if (!selected.length || selected.length > 10_000 || new Set(selected).size !== selected.length || selected.some(p => !available.includes(p))) {
      throw new Error("Choose files from the current task comparison.");
    }
    matchingImages(repo.root, from, selected);
    for (const path of selected) if (imageAt(to, path).kind === "unsupported") throw new Error(`${path} has no restorable starting snapshot.`);
    const plan: RestorePlan = { id: crypto.randomUUID(), runId, action: undo ? "undo" : "discard", recoveryID: recovery?.id,
      paths: selected, createdAt: Date.now(), repository: repo, from, to };
    for (const [id, existing] of this.plans) if (Date.now() - existing.createdAt > 120_000) this.plans.delete(id);
    this.plans.set(plan.id, plan);
    return { id: plan.id, paths: plan.paths, action: plan.action, repository: repo.root, expiresAt: plan.createdAt + 120_000 };
  }

  async apply(planID: string) {
    const plan = this.plans.get(planID); this.plans.delete(planID);
    if (!plan || Date.now() - plan.createdAt > 120_000) throw new Error("This restore preview expired. Review the files again.");
    const root = plan.repository.root;
    if (this.restoring.has(root) || [...this.active.values()].some(task => task.repository.root === root)) throw new Error("A task or restoration is using this repository. Try again when it finishes.");
    this.restoring.add(root);
    try {
      const repo = await repository(root);
      if (!repo || !sameRepository(repo, plan.repository)) throw new Error("The Git branch or staging state changed. Refresh before restoring files.");
      matchingImages(root, plan.from, plan.paths);
      if (plan.conversationID) return applySession(this.storage, plan);
      const task = this.storage.task(plan.runId);
      if (!task) throw new Error("This task snapshot expired. Project files were kept unchanged.");
      const pick = (source: Record<string, FileImage>, paths: string[]) => Object.fromEntries(paths.map(path => [path, imageAt(source, path)]));
      const recovery: RecoveryRecord = { id: crypto.randomUUID(), runId: plan.runId, createdAt: Date.now(), repository: repo,
        before: pick(plan.from, plan.paths), after: pick(plan.to, plan.paths), undone: false };
      // Recovery must reach disk before any user file is changed, including Undo.
      this.storage.saveRecovery(recovery);
      if (!this.storage.recovery(recovery.id)) throw new Error("The recovery storage limit was reached. No files were changed.");
      const result = applyRestore(plan);
      recovery.before = pick(plan.from, result.applied); recovery.after = pick(plan.to, result.applied);
      recovery.undone = plan.action === "undo" || result.applied.length === 0;
      this.storage.saveRecovery(recovery);
      for (const file of task.files) if (result.applied.includes(file.path)) file.discarded = plan.action === "discard";
      this.storage.saveTask(task);
      if (plan.action === "undo" && plan.recoveryID) {
        const original = this.storage.recovery(plan.recoveryID);
        if (original) {
          original.remainingPaths = (original.remainingPaths ?? Object.keys(original.before)).filter(path => !result.applied.includes(path));
          original.undone = original.remainingPaths.length === 0;
          this.storage.saveRecovery(original);
        }
      }
      return { ...result, notice: result.failures.length ? `Some files were kept unchanged. ${result.failures.join(" ")}`
        : plan.action === "undo" ? "Discard undone. Changes restored." : "Changes discarded. Undo is available while the local recovery copy is kept.", task: this.summary(task) };
    } finally { this.restoring.delete(root); }
  }

  private busy(root: string) {
    return this.restoring.has(root) || [...this.active.values()].some(task => task.repository.root === root);
  }

  async workingStatus(workspace: string) {
    const repo = await repository(workspace);
    return repo ? workingStatus(repo, this.busy(repo.root)) : { repository: null, canCommit: false, canPush: false, remotes: [], ahead: 0, behind: 0, head: "", busy: false };
  }

  async sessionStatus(workspace: string, conversationID: string) {
    const repo = await repository(workspace);
    return repo ? sessionSafety(this.storage, repo, conversationID, this.busy(repo.root))
      : { repository: null, hasChanges: false, canRevert: false, canUndo: false, reason: "Choose a Git repository." };
  }

  async previewSession(workspace: string, conversationID: string, undo = false) {
    const repo = await repository(workspace);
    if (!repo) throw new Error("Choose a Git repository.");
    const plan = previewSession(this.storage, repo, conversationID, this.busy(repo.root), undo);
    this.plans.set(plan.id, plan);
    return { id: plan.id, paths: plan.paths, action: plan.action, repository: repo.root, scope: "session" };
  }

  private async mutate<T>(workspace: string, operation: (repo: Repository) => Promise<T>) {
    const repo = await repository(workspace);
    if (!repo) throw new Error("Choose a Git repository.");
    if (this.busy(repo.root)) throw new Error("Wait for active tasks and Git operations to finish.");
    this.restoring.add(repo.root);
    try { return await operation(repo); } finally { this.restoring.delete(repo.root); }
  }

  async previewCommit(workspace: string, scope: string, id: string | undefined, paths: string[], branch: string) {
    const repo = await repository(workspace);
    if (!repo || this.busy(repo.root)) throw new Error("Wait for active tasks and Git operations to finish.");
    const view = scope === "session" && id ? await this.sessionReview(workspace, id) : await this.review(workspace, scope === "task" ? id : undefined, scope === "project");
    if (scope === "task" && !view.task) throw new Error("This task comparison is unavailable.");
    return this.working.preview(repo, view.files, paths, branch);
  }

  async commit(planID: string, message: string) {
    const plan = this.working.take(planID);
    return this.mutate(plan.repository.root, repo => this.working.commit(repo, plan, message));
  }

  async push(workspace: string, input: { head: string; branch: string; remote: string; remoteBranch: string }) {
    return this.mutate(workspace, repo => this.working.push(repo, input));
  }

  private latestRecovery(runId: string) {
    return this.storage.recoveries().filter(r => r.runId === runId && !r.undone).sort((a, b) => b.createdAt - a.createdAt)[0];
  }
  settings(enabled?: boolean, clear = false) {
    if ((enabled !== undefined || clear) && (this.active.size || this.restoring.size)) throw new Error("Finish active tasks before changing local Git snapshots.");
    if (enabled !== undefined) { this.storage.setEnabled(enabled); if (!enabled) clear = true; }
    if (clear) { this.storage.clear(); this.plans.clear(); }
    return this.storage.status();
  }
}
