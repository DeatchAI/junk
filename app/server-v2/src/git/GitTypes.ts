export interface Repository { root: string; gitDir: string; branch: string; head: string; indexHash: string }
export interface FileImage { kind: "file" | "missing" | "unsupported"; hash: string; data?: string; mode?: number; size: number; reason?: string }
export interface FileChange {
  path: string; previousPath?: string; status: string; additions: number; deletions: number;
  binary: boolean; reason?: string; staged?: boolean; earlier?: boolean; discarded?: boolean; diff: string;
}
export interface TaskRecord {
  runId: string; conversationID?: string; messageOrdinal?: number; promptHash: string; startedAt: number; completedAt: number;
  repository: Repository; mixed: boolean; notice?: string; before: Record<string, FileImage>;
  after: Record<string, FileImage>; files: FileChange[];
}
export interface RecoveryRecord {
  id: string; runId: string; createdAt: number; repository: Repository;
  before: Record<string, FileImage>; after: Record<string, FileImage>; undone: boolean;
  conversationID?: string; remainingPaths?: string[];
}
export interface RestorePlan {
  id: string; runId: string; action: "discard" | "undo"; recoveryID?: string;
  paths: string[]; createdAt: number; repository: Repository; from: Record<string, FileImage>; to: Record<string, FileImage>;
  conversationID?: string; sessionRunIDs?: string[];
}
export const missingImage = (): FileImage => ({ kind: "missing", hash: "missing", size: 0 });
export const imageAt = (images: Record<string, FileImage>, path: string) => Object.hasOwn(images, path) ? images[path]! : missingImage();
