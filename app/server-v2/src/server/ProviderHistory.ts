import type { ClientMessage } from "../protocol/messages";
import { nativeHistory, type ServerWebSocket } from "./RuntimeContext";
import { send } from "./RuntimeHelpers";

export async function handleProviderHistory(ws: ServerWebSocket, message: ClientMessage) {
  if (!["list_conversations", "get_conversation", "get_conversation_branches", "delete_conversation", "delete_message", "edit_message", "search", "search_conversations",
    "refresh_provider_history", "restore_hidden_history", "discover_chats", "preview_chat_import", "import_chats"].includes(message.type)) return false;
  try {
    switch (message.type) {
      case "list_conversations":
        send(ws, { type: "conversations_list", ...nativeHistory.list(message.limit, message.offset, message.refreshLoaded === true) });
        send(ws, { type: "provider_history_status", ...nativeHistory.status });
        break;
      case "refresh_provider_history":
        void nativeHistory.refresh(true);
        send(ws, { type: "provider_history_status", ...nativeHistory.status });
        break;
      case "restore_hidden_history":
        nativeHistory.restoreHidden();
        send(ws, { type: "conversations_list", ...nativeHistory.list() });
        break;
      case "get_conversation": {
        const entry = await nativeHistory.get(message.conversationId);
        if (!entry) throw new Error("Conversation is unavailable. Refresh provider history.");
        send(ws, { type: "conversation", ...entry });
        break;
      }
      case "get_conversation_branches": {
        await nativeHistory.get(message.conversationId);
        send(ws, nativeHistory.index.branchState(message.conversationId));
        break;
      }
      case "delete_conversation":
        nativeHistory.hide(message.conversationId);
        send(ws, { type: "deleted", id: message.conversationId });
        break;
      case "delete_message": case "edit_message":
        throw new Error("History is owned by its provider. Detach does not edit or delete saved provider messages. Start a new native chat to branch your work.");
      case "search":
        send(ws, { type: "search_results", results: nativeHistory.searchMessages(message.query, message.limit) });
        break;
      case "search_conversations":
        if (typeof message.requestId !== "string" || message.requestId.length > 100 || typeof message.query !== "string") throw new Error("Invalid history search.");
        send(ws, { type: "history_search_results", requestId: message.requestId, query: message.query,
          conversations: nativeHistory.search(message.query), indexing: nativeHistory.status.indexing });
        break;
      default:
        send(ws, { type: "chat_import_error", requestId: (message as { requestId: string }).requestId,
          error: "Manual import has been replaced by automatic provider history discovery. Refresh history to see your sessions." });
    }
  } catch (error) { send(ws, { type: "history_error", error: error instanceof Error ? error.message : "Provider history is unavailable." }); }
  return true;
}
