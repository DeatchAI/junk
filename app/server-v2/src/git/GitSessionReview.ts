import { fileChange } from "./GitDiff";
import { imageAt, type FileChange, type FileImage, type RecoveryRecord, type TaskRecord } from "./GitTypes";

export function sessionImages(tasks: TaskRecord[], recoveries: RecoveryRecord[] = []) {
  const images = new Map<string, { before: FileImage; after: FileImage }>();
  let coherent = true;
  const events = [
    ...tasks.map(task => ({ at: task.completedAt, task, recovery: undefined as RecoveryRecord | undefined })),
    ...recoveries.map(recovery => ({ at: recovery.createdAt, task: undefined as TaskRecord | undefined, recovery })),
  ].sort((a, b) => a.at - b.at || Number(Boolean(b.task)) - Number(Boolean(a.task)));
  function append(path: string, before: FileImage, after: FileImage) {
    const previous = images.get(path);
    if (previous && previous.after.hash !== before.hash) coherent = false;
    images.set(path, { before: previous?.before ?? before, after });
  }
  for (const event of events) {
    if (event.task) {
      const task = event.task;
      for (const file of task.files) {
        for (const path of [file.path, ...(file.previousPath ? [file.previousPath] : [])]) {
          append(path, imageAt(task.before, path), imageAt(task.after, path));
        }
      }
    } else if (event.recovery) {
      for (const path of Object.keys(event.recovery.after)) {
        append(path, imageAt(event.recovery.before, path), imageAt(event.recovery.after, path));
      }
    }
  }
  const changed = [...images].filter(([, value]) => value.before.hash !== value.after.hash);
  return { coherent, paths: changed.map(([path]) => path).sort(),
    before: Object.fromEntries(changed.map(([path, value]) => [path, value.before])),
    after: Object.fromEntries(changed.map(([path, value]) => [path, value.after])) };
}

/** Compare captured contents only; never substitute the working tree for missing historical contents. */
export async function sessionChanges(tasks: TaskRecord[], recoveries: RecoveryRecord[] = []): Promise<FileChange[]> {
  const images = sessionImages(tasks, recoveries), files: FileChange[] = [];
  for (const path of images.paths) files.push(await fileChange(path, images.before[path]!, images.after[path]!));
  return files;
}
