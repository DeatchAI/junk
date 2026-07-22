import { homedir } from "node:os";
import { dirname, join } from "node:path";

export function defaultDatabasePath() {
  if (Bun.env.DETACH_DATABASE_PATH?.trim()) {
    return Bun.env.DETACH_DATABASE_PATH.trim();
  }
  return join(defaultDataDir(), "chats.sqlite");
}

export function defaultDataDir() {
  if (Bun.env.DETACH_DATABASE_PATH?.trim()) {
    return dirname(Bun.env.DETACH_DATABASE_PATH.trim());
  }
  return Bun.env.DETACH_DATA_DIR?.trim() || join(homedir(), "Library", "Application Support", "Detach");
}
