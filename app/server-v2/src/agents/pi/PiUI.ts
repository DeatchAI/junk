import type { AgentStreamCallbacks } from "../AgentAdapter";
import { getString } from "../CliAdapterUtils";

export async function answerPiUI(frame: Record<string, unknown>, callbacks: AgentStreamCallbacks) {
  const id = getString(frame.id), method = getString(frame.method);
  if (!id || !method) return;
  const title = getString(frame.title) || "Pi needs your answer";
  if (method === "confirm") {
    const approved = await callbacks.onPermission?.({
      title, description: getString(frame.message) || title, riskLevel: "normal",
    }) ?? false;
    return { type: "extension_ui_response", id, confirmed: approved };
  }
  if (["select", "input", "editor"].includes(method)) {
    const labels = Array.isArray(frame.options) ? frame.options.filter((option): option is string => typeof option === "string") : [];
    if (method === "select" && labels.length > 6) return answerPagedSelect(id, title, labels, callbacks);
    const answers = await callbacks.onQuestion?.({ questions: [{
      id: "answer", header: method === "select" ? "Choose" : "Answer", question: title,
      ...(labels.length ? { options: labels.map((label) => ({ label })) } : {}),
    }] });
    const value = answers?.answer?.answers[0];
    // A select can only accept one of the supplied choices, never an invented option.
    if (!value || (method === "select" && !labels.includes(value))) {
      return { type: "extension_ui_response", id, cancelled: true };
    }
    return { type: "extension_ui_response", id, value };
  }
  if (["notify", "setStatus"].includes(method)) {
    const status = getString(frame.message) || getString(frame.statusText);
    if (status) callbacks.onActivity(status);
  } else if (method === "cancel") {
    return;
  } else if (!["setWidget", "setTitle", "set_editor_text"].includes(method)) {
    // Unknown blocking surfaces must fail closed, not hang the run.
    return { type: "extension_ui_response", id, cancelled: true };
  }
}

async function answerPagedSelect(id: string, title: string, labels: string[], callbacks: AgentStreamCallbacks) {
  let page = 0;
  while (true) {
    const choices = labels.slice(page * 4, page * 4 + 4);
    let next = "More choices", previous = "Previous choices";
    while (labels.includes(next)) next += " →";
    while (labels.includes(previous)) previous += " ←";
    const options = [...choices, ...(page > 0 ? [previous] : []),
      ...(page * 4 + 4 < labels.length ? [next] : [])];
    const response = await callbacks.onQuestion?.({ questions: [{
      id: "answer", header: "Choose", question: title + ` (page ${page + 1})`,
      options: options.map((label) => ({ label })),
    }] });
    const value = response?.answer?.answers[0];
    if (value === next && options.includes(next)) { page += 1; continue; }
    if (value === previous && page > 0) { page -= 1; continue; }
    return value && labels.includes(value) ? { type: "extension_ui_response", id, value }
      : { type: "extension_ui_response", id, cancelled: true };
  }
}
