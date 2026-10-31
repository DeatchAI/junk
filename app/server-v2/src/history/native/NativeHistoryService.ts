import type { AgentKind, Conversation, Message, SearchResult } from "../../protocol/messages";
import type { ExternalChat, ImportSource } from "../../imports/ImportTypes";
import type { SqliteHistory } from "../SqliteHistory";
import { NativeHistoryIndex } from "./NativeHistoryIndex";
import { nativeConversationID, nativeSourceKey } from "./NativeIdentity";
import { nativeHistorySources } from "./NativeSources";
import { title } from "../../imports/Transcript";

export interface HistorySyncStatus { syncing: boolean; indexing: boolean; pending: number; indexedChats: number; notices: string[]; revision: number; catalogRevision: number }

/** Poll provider metadata; lazily hydrate display history and incrementally build a disposable FTS index. */
export class NativeHistoryService {
  private refreshJob?: Promise<void>;
  private lastRefresh = 0;
  private notices = new Map<AgentKind, string[]>();
  private queue = new Map<string, ExternalChat>();
  private workers = 0;
  private active = new Set<string>();
  private awaitingDiscovery = new Map<string, AgentKind>();
  private stopped = false;
  private cacheEpoch = 0;
  private backgroundCachePaused = false;
  private revision = 0;
  private catalogRevision = 0;
  constructor(readonly index: NativeHistoryIndex, private readonly legacy: SqliteHistory,
    private readonly sources: ImportSource[] = nativeHistorySources(), private readonly notify: () => void = () => {}) {}

  get status(): HistorySyncStatus {
    return { syncing: Boolean(this.refreshJob), indexing: this.workers > 0 || this.queue.size > 0,
      pending: this.queue.size + this.workers, indexedChats: this.index.count(), notices: [...this.notices.values()].flat(),
      revision: this.revision, catalogRevision: this.catalogRevision };
  }
  source(provider: AgentKind) { return this.sources.find((source) => source.provider === provider); }
  refresh(force = false) {
    if (force) this.backgroundCachePaused = false;
    if (this.refreshJob) return this.refreshJob;
    if (this.stopped || (!force && Date.now() - this.lastRefresh < 15_000)) return Promise.resolve();
    this.lastRefresh = Date.now();
    this.refreshJob = Promise.resolve().then(async () => {
      await Promise.all(this.sources.map(async (source) => {
        try {
          const result = await source.discover(); this.notices.set(source.provider, result.notices ?? []);
          for (const chat of result.chats) {
            const id = nativeConversationID(chat.sourceKey);
            this.awaitingDiscovery.delete(id);
            if (!this.active.has(id)) this.index.upsert(chat);
            if (this.index.searchCacheEnabled && !this.backgroundCachePaused && !chat.active && this.index.needsMessages(chat)) this.queue.set(chat.sourceKey, chat);
          }
          if (result.complete === true) this.index.reconcile(source.provider, new Set([
            ...result.chats.map((chat) => chat.sourceKey),
            ...[...this.awaitingDiscovery].flatMap(([id, provider]) => {
              const chat = this.index.source(id); return provider === source.provider && chat ? [chat.sourceKey] : [];
            }),
            ...[...this.active].flatMap((id) => { const chat = this.index.source(id); return chat?.provider === source.provider ? [chat.sourceKey] : []; }),
          ]));
        } catch {
          this.index.markUnavailable(source.provider);
          this.notices.set(source.provider, [`${source.provider}: history unavailable. Check installation, login, folder access, or provider session support.`]);
        }
        this.changed();
      }));
    }).finally(() => { this.refreshJob = undefined; this.changed(false); this.pump(); });
    this.changed(false);
    return this.refreshJob;
  }
  list(limit = 500, offset = 0, refreshLoaded = false) {
    limit = Number.isFinite(limit) ? Math.max(1, Math.min(refreshLoaded ? 10_000 : 500, Math.trunc(limit))) : 500;
    offset = Number.isFinite(offset) ? Math.max(0, Math.trunc(offset)) : 0;
    const all = this.all();
    return { conversations: all.slice(offset, offset + limit), offset, hasMore: all.length > offset + limit };
  }
  async get(id: string) {
    const source = this.index.source(id);
    if (!source) {
      const entry = this.legacy.get(id);
      return entry ? { ...entry, conversation: { ...entry.conversation, origin: "legacy" as const, canResume: false } } : undefined;
    }
    if (this.active.has(id)) return this.index.get(id);
    try { return await this.readSource(source); }
    catch {
      const cached = this.index.get(id);
      if (!cached?.messages.length) throw new Error("Provider history could not be read. Check its login, CLI version, and folder permissions.");
      return { ...cached, conversation: { ...cached.conversation, canResume: false, historyWarning: "Provider unavailable; showing cached history. Reconnect before continuing." } };
    }
  }
  async readSource(chat: ExternalChat) {
    const cacheEpoch = this.cacheEpoch;
    const source = this.source(chat.provider); if (!source) throw new Error("Provider history adapter unavailable.");
    if (!chat.locator && ["claude", "pi", "omp"].includes(chat.provider)) {
      const found = (await source.discover()).chats.find((entry) => entry.sourceId === chat.sourceId);
      if (!found) throw new Error("Saved provider session not found.");
      chat = found;
    }
    const messages = await source.read(chat);
    if (!this.index.hasSource(chat.sourceKey)) throw new Error("Provider session disappeared during history refresh.");
    // A background replay must never replace a newer in-flight turn's cache.
    if (this.active.has(nativeConversationID(chat.sourceKey))) return this.index.get(nativeConversationID(chat.sourceKey))!;
    if (cacheEpoch !== this.cacheEpoch) return { conversation: this.index.conversation(chat), messages: this.index.displayMessages(chat, messages) };
    return this.index.cache(chat, messages);
  }
  search(query: string, limit = 100) {
    query = query.trim().slice(0, 512); if (!query) return [];
    const hits = this.index.searchChats(query, limit); const snippets = new Map(hits.map((hit) => [hit.conversation_id, hit.snippet]));
    for (const hit of this.legacy.search(query, limit * 3)) if (!this.legacyAlias(hit.conversation_id)) snippets.set(hit.conversation_id, hit.snippet);
    return this.all()
      .filter((entry) => snippets.has(entry.id) || [entry.title, entry.provider, entry.workspacePath].some((value) => value?.toLocaleLowerCase().includes(query.toLocaleLowerCase())))
      .sort((a, b) => b.updated_at - a.updated_at).slice(0, Math.max(1, Math.min(100, limit)))
      .map((entry) => ({ ...entry, ...(snippets.has(entry.id) ? { searchSnippet: snippets.get(entry.id) } : {}) }));
  }
  searchMessages(query: string, limit = 100): SearchResult[] {
    query = query.trim().slice(0, 512);
    limit = Number.isFinite(limit) ? Math.max(1, Math.min(100, Math.trunc(limit))) : 100;
    return [...this.index.search(query, limit), ...this.legacy.search(query, limit).filter((hit) => !this.legacyAlias(hit.conversation_id))]
      .sort((a, b) => b.created_at - a.created_at).slice(0, limit);
  }
  register(provider: AgentKind, sessionID: string, workspacePath: string, prompt: string, options: { locator?: string; title?: string; model?: string; canResume?: boolean } = {}) {
    const chat: ExternalChat = { provider, sourceId: sessionID, sourceKey: nativeSourceKey(provider, sessionID), workspacePath,
      locator: options.locator, title: title(options.title || prompt), model: options.model, createdAt: Date.now(), updatedAt: Date.now(),
      canResume: options.canResume !== false };
    const existing = this.index.source(nativeConversationID(chat.sourceKey));
    if (existing) Object.assign(chat, { ...existing, title: options.title || existing.title,
      locator: options.locator ?? existing.locator, model: options.model ?? existing.model, canResume: options.canResume ?? existing.canResume });
    chat.updatedAt = Date.now();
    const id = this.index.upsert(chat); this.queue.delete(chat.sourceKey); this.active.add(id); this.awaitingDiscovery.set(id, provider); this.changed(); return id;
  }
  updateTitle(id: string, value: string) {
    const chat = this.index.source(id); if (!chat) return;
    this.index.upsert({ ...chat, title: title(value) }); this.changed();
  }
  lock(id: string) { if (this.active.has(id)) throw new Error("This native session is already running in Detach."); this.active.add(id); }
  async finish(id: string) {
    if (!id) return;
    this.active.delete(id);
    const chat = this.index.source(id);
    if (chat) await this.readSource(chat).catch(() => undefined);
    this.changed(); this.pump();
  }
  hide(id: string) { if (this.index.source(id)) this.index.hide(id); else this.index.hideKey(`legacy:${id}`); this.changed(); }
  restoreHidden() { this.index.restoreHidden(); this.changed(); }
  get cacheStatus() { return this.index.cacheStatus; }
  configureSearchCache(enabled: boolean) {
    this.cacheEpoch++;
    this.queue.clear();
    this.index.setSearchCacheEnabled(enabled);
    this.changed(false);
    if (enabled) void this.refresh(true);
  }
  clearSearchCache() {
    this.cacheEpoch++;
    this.backgroundCachePaused = true;
    this.queue.clear();
    this.index.clearSearchCache();
    this.changed(false);
  }
  stop() { this.stopped = true; this.queue.clear(); }
  private legacyAlias(id: string) {
    if (this.index.isHidden(`legacy:${id}`)) return true;
    const source = this.legacy.metadata.importedSource(id);
    return source ? this.index.hasSource(source.sourceKey) || Boolean(source.sessionID && this.index.hasSource(nativeSourceKey(source.provider, source.sessionID))) : false;
  }
  private all(): Conversation[] {
    return [...this.index.list(), ...this.legacy.list(1_000_000).filter((entry) => !this.legacyAlias(entry.id))
      .map((entry) => ({ ...entry, origin: "legacy" as const, canResume: false }))]
      .sort((a, b) => b.updated_at - a.updated_at || a.id.localeCompare(b.id));
  }
  private pump() {
    if (this.stopped || this.active.size || !this.index.searchCacheEnabled || this.backgroundCachePaused) return;
    while (this.workers < 2 && this.queue.size) {
      const next = [...this.queue.values()].find((chat) => !this.active.has(nativeConversationID(chat.sourceKey)));
      if (!next) break;
      this.queue.delete(next.sourceKey);
      const current = this.index.source(nativeConversationID(next.sourceKey));
      if (!current || current.active || !this.index.needsMessages(current)) continue;
      this.workers++;
      void this.readSource(current).catch(() => {}).finally(() => { this.workers--; this.changed(false); this.pump(); });
    }
  }
  private changed(catalog = true) { this.revision++; if (catalog) this.catalogRevision++; this.notify(); }
}
