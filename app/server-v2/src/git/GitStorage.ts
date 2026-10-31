import { chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { defaultDataDir } from "../history/databasePath";
import { digest } from "./GitRepository";
import type { RecoveryRecord, TaskRecord } from "./GitTypes";

export class GitStorage {
  constructor(readonly directory = join(defaultDataDir(), "git-review")) {
    for (const part of [directory, ...["tasks", "recovery", "task-meta", "recovery-meta"].map(type => join(directory, type))]) {
      mkdirSync(part, { recursive: true, mode: 0o700 }); chmodSync(part, 0o700);
    }
    this.prune();
  }
  get enabled() {
    try { return JSON.parse(readFileSync(join(this.directory, "settings.json"), "utf8")).enabled !== false; }
    catch { return true; }
  }
  setEnabled(enabled: boolean) {
    this.atomic(join(this.directory, "settings.json"), { enabled });
  }
  tasks() { this.prune(); return this.readAll<TaskRecord>("task-meta"); }
  recoveries() { this.prune(); return this.readAll<RecoveryRecord>("recovery-meta"); }
  task(id: string) { this.prune(); return this.read<TaskRecord>("tasks", id); }
  recovery(id: string) { this.prune(); return this.read<RecoveryRecord>("recovery", id); }
  saveTask(task: TaskRecord) {
    this.atomic(this.path("tasks", task.runId), task);
    this.atomic(this.path("task-meta", task.runId), { ...task, before: {}, after: {}, files: task.files.map(file => ({ ...file, diff: "" })) });
    this.prune();
  }
  saveRecovery(recovery: RecoveryRecord) {
    this.atomic(this.path("recovery", recovery.id), recovery);
    this.atomic(this.path("recovery-meta", recovery.id), { ...recovery, before: {}, after: {} });
    this.prune();
  }
  status() {
    const tasks = this.tasks(), recovery = this.recoveries();
    const bytes = ["tasks", "recovery"].reduce((n, type) => n + this.entries(type).reduce((sum, p) => sum + statSync(p).size, 0), 0);
    return { enabled: this.enabled, taskCount: tasks.length, recoveryCount: recovery.filter(r => !r.undone).length, bytes };
  }
  clear() {
    for (const type of ["tasks", "recovery", "task-meta", "recovery-meta"]) for (const path of this.entries(type)) rmSync(path, { force: true });
  }
  private path(type: string, id: string) { return join(this.directory, type, digest(id) + ".json"); }
  private read<T>(type: string, id: string): T | undefined {
    try { return JSON.parse(readFileSync(this.path(type, id), "utf8")); } catch { return undefined; }
  }
  private readAll<T>(type: string): T[] {
    return this.entries(type).flatMap(path => { try { return [JSON.parse(readFileSync(path, "utf8")) as T]; } catch { return []; } });
  }
  private entries(type: string) { return readdirSync(join(this.directory, type)).filter(name => name.endsWith(".json")).map(name => join(this.directory, type, name)); }
  private atomic(path: string, value: unknown) {
    const temporary = path + "." + crypto.randomUUID() + ".tmp";
    try { writeFileSync(temporary, JSON.stringify(value), { mode: 0o600, flag: "wx" }); renameSync(temporary, path); }
    finally { rmSync(temporary, { force: true }); }
  }
  private prune() {
    const now = Date.now();
    for (const [type, count, age, budget] of [["tasks", 100, 30, 128], ["recovery", 10, 7, 128]] as const) {
      let bytes = 0;
      const paths = this.entries(type).sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
      paths.forEach((path, i) => {
        if (!existsSync(path)) return;
        const stat = statSync(path); bytes += stat.size;
        if (i >= count || now - stat.mtimeMs > age * 86400_000 || bytes > budget * 1024 * 1024) rmSync(path, { force: true });
      });
      const metadata = type === "tasks" ? "task-meta" : "recovery-meta";
      for (const path of this.entries(metadata)) {
        if (!existsSync(join(this.directory, type, path.split(/[\\/]/).at(-1)!))) rmSync(path, { force: true });
      }
    }
  }
}
