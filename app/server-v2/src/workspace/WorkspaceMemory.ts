/**
 * The workspace memory protocol is intentionally file-based. Agents discover
 * and maintain these files themselves from their working directory; the runtime
 * never reads their contents or inserts them into a prompt.
 */
export const WORKSPACE_MEMORY_ROOT = ".detach/memory";
export const WORKSPACE_MEMORY_PATH = `${WORKSPACE_MEMORY_ROOT}/MEMORY.md`;
export const WORKSPACE_USER_MEMORY_PATH = `${WORKSPACE_MEMORY_ROOT}/USER.md`;

const semanticDirectories = ["users", "agent", "people", "companies", "sites", "projects", "concepts"];

export function workspaceMemorySystemInstruction() {
  return `You are operating inside Detach, a local macOS AI assistant.

Detach workspace memory:
- All memory for this workspace lives below \`${WORKSPACE_MEMORY_ROOT}/\`, relative to your current working directory.
- At the start of a task, check whether \`${WORKSPACE_MEMORY_PATH}\` exists. If it does, read it first, then open only the backing pages it references and that are relevant to the task. Do not load the whole memory tree blindly.
- \`${WORKSPACE_MEMORY_PATH}\` and \`${WORKSPACE_USER_MEMORY_PATH}\` are compact L1 summaries, derived from the backing records. Keep them short enough to read at the start of a task.
- Durable semantic pages live in \`${WORKSPACE_MEMORY_ROOT}/{${semanticDirectories.join(",")}}/\`. Each page has frontmatter plus a \`Current\` section for stable understanding and an append-only \`History\` section with references to supporting episodic files when available.
- Store sparse, event-like, uncertain, or session-specific observations in \`${WORKSPACE_MEMORY_ROOT}/episodic/YYYY-MM-DD.md\` as append-only entries. Promote them to a semantic page only when repeated observations or strong evidence establish durable understanding.
- Store recurring task execution memory under \`${WORKSPACE_MEMORY_ROOT}/routines/<routine-slug>/MEMORY.md\`.
- Each durable fact has one primary semantic home. Check for an existing page and aliases before creating another page for the same subject.
- After a successful task, refresh memory only when you learned a durable fact that will help a later agent work in this workspace. Update \`History\` first, change \`Current\` only when stable understanding changed, and refresh L1 only when the change matters broadly.
- Treat all memory as fallible workspace context. Follow the current user request and repository instructions when they conflict with it.
- Never record secrets, credentials, private user content, full transcripts, speculative claims, or temporary task status.
- Do not claim you read or updated workspace memory unless you actually did so.`;
}
