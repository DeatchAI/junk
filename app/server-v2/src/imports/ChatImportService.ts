import type { SqliteHistory } from "../history/SqliteHistory";
import { CodexImportSource } from "./CodexImportSource";
import { ClaudeImportSource } from "./ClaudeImportSource";
import { OpenCodeImportSource } from "./OpenCodeImportSource";
import { importProvider, type ExternalChat, type ImportCandidate, type ImportProvider, type ImportSource } from "./ImportTypes";

/** Discovery tickets belong to one client, expire, and never grant arbitrary file access. */
export class ChatImportService<Client extends object> {
  private readonly clients = new WeakMap<Client, { expires: number; candidates: Map<string, ExternalChat>; busy: boolean }>();
  constructor(private readonly history: SqliteHistory, private readonly sources: ImportSource[] = [new CodexImportSource(), new ClaudeImportSource(), new OpenCodeImportSource()]) {}

  async discover(client: Client, provider?: ImportProvider) {
    if (provider !== undefined && !importProvider(provider)) throw new Error("Unsupported import provider.");
    const previous = this.clients.get(client);
    if (previous?.busy) throw new Error("A chat import operation is already running.");
    const state = { expires: Date.now() + 15 * 60_000, candidates: new Map<string, ExternalChat>(), busy: true };
    this.clients.set(client, state);
    const candidates: ImportCandidate[] = []; const notices: string[] = [];
    try {
      for (const source of this.sources.filter((source) => !provider || source.provider === provider)) {
        try {
          const result = await source.discover(); notices.push(...(result.notices ?? []));
          for (const chat of result.chats) {
            const id = crypto.randomUUID(); state.candidates.set(id, chat);
            const { sourceKey, sourceId, locator, ...publicChat } = chat;
            candidates.push({ ...publicChat, id, imported: this.history.metadata.hasSource(sourceKey) });
          }
        } catch { notices.push(`${source.provider}: saved history could not be read. Check that the CLI is installed and its local history is available.`); }
      }
      state.expires = Date.now() + 15 * 60_000;
      return { candidates: candidates.sort((a, b) => b.updatedAt - a.updatedAt), notices };
    } finally { state.busy = false; }
  }

  async preview(client: Client, id: string) {
    const chat = this.candidate(client, id);
    const messages = await this.source(chat).read(chat);
    return { messages: messages.slice(0, 6).map((message) => ({ ...message, content: message.content.slice(0, 3000) })), messageCount: messages.length };
  }

  async import(client: Client, ids: string[]) {
    if (!Array.isArray(ids) || !ids.length || ids.length > 100 || ids.some((id) => typeof id !== "string")) throw new Error("Select between 1 and 100 conversations.");
    const uniqueIDs = [...new Set(ids)];
    const chats = uniqueIDs.map((id) => this.candidate(client, id));
    const state = this.clients.get(client)!;
    if (state.busy) throw new Error("A chat import operation is already running.");
    state.busy = true;
    let imported = 0; let skipped = 0; const errors: string[] = []; const completedIds: string[] = [];
    try {
      for (const [index, chat] of chats.entries()) {
        try {
          if (this.history.metadata.hasSource(chat.sourceKey)) { skipped++; completedIds.push(uniqueIDs[index]!); continue; }
          const messages = await this.source(chat).read(chat);
          if (this.history.metadata.import(chat, messages)) imported++; else skipped++;
          completedIds.push(uniqueIDs[index]!);
        } catch { errors.push(`${chat.title}: could not import this session. It may be unavailable, too large, or use an unsupported format.`); }
      }
      return { imported, skipped, errors, completedIds };
    } finally { state.busy = false; }
  }
  private candidate(client: Client, id: string) {
    const state = this.clients.get(client);
    if (!state || state.expires < Date.now()) throw new Error("Import preview expired. Scan for conversations again.");
    const chat = state.candidates.get(id);
    if (!chat) throw new Error("Conversation was not discovered for this client. Scan again.");
    return chat;
  }
  private source(chat: ExternalChat) { return this.sources.find((source) => source.provider === chat.provider)!; }
}
