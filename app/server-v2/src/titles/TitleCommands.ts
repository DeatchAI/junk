import type { AgentKind } from "../protocol/messages";
import { TITLE_INSTRUCTIONS } from "./TitleText";

export interface TitleCommand { args: string[]; env?: Record<string, string>; input?: string }

/** These are isolated inference calls, never normal workspace agent runs. */
export function titleCommand(agent: AgentKind, model: string | undefined, effort: string | undefined,
  prompt: string, files: { prompt: string; ampSettings: string }): TitleCommand | undefined {
  const selected = model ? ["--model", model] : [];
  switch (agent) {
    case "codex":
      return { args: [
        "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check",
        "--sandbox", "read-only", "--json", "--color", "never",
        "-c", 'approval_policy="never"', "-c", 'web_search="disabled"',
        "-c", "mcp_servers={}", "-c", "project_doc_max_bytes=0",
        ...["shell_tool", "code_mode", "plugins", "multi_agent", "request_permissions_tool", "js_repl", "skill_search"]
          .flatMap((flag) => ["--disable", flag]),
        ...(effort ? ["-c", "model_reasoning_effort=" + JSON.stringify(effort)] : []),
        ...selected, "-",
      ], input: prompt };
    case "claude":
      return { args: [
        "--print", "--output-format", "json", "--no-session-persistence",
        "--tools", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--setting-sources", "user", "--settings", '{"disableAllHooks":true}',
        "--system-prompt", TITLE_INSTRUCTIONS, ...selected,
        ...(effort ? ["--effort", effort] : []),
      ], input: prompt, env: { CLAUDE_CODE_SKIP_PROMPT_HISTORY: "1" } };
    case "grok":
      return { args: [
        "--prompt-file", files.prompt, "--verbatim", "--output-format", "plain",
        "--system-prompt-override", TITLE_INSTRUCTIONS, "--tools", "", "--deny", "*",
        "--no-subagents", "--disable-web-search", "--no-memory", "--no-plan", "--max-turns", "1", ...selected,
      ], env: { GROK_CURSOR_MCPS_ENABLED: "false", GROK_CLAUDE_MCPS_ENABLED: "false" } };
    case "pi":
      return { args: [
        "--print", "--no-session", "--no-tools", "--no-mcp", "--no-extensions",
        "--no-skills", "--no-prompt-templates", "--no-themes", "--no-context-files",
        "--system-prompt", TITLE_INSTRUCTIONS, ...selected,
      ], input: prompt };
    case "omp":
      return { args: [
        "--print", "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-rules",
        "--no-lsp", "--no-pty", "--no-title", "--system-prompt", TITLE_INSTRUCTIONS,
        ...selected, ...(effort ? ["--thinking", effort] : []),
      ], input: prompt, env: { PI_NO_TITLE: "1" } };
    case "amp":
      return { args: [
        "--execute", "--stream-json", "--no-color", "--no-ide", "--settings-file", files.ampSettings,
        ...(model ? ["--mode", model] : []),
      ], input: prompt, env: { AMP_SKIP_UPDATE_CHECK: "1", AMP_REMOTE_CONTROL_TERMINAL: "0" } };
    // Cursor's ACP flow does not provide a safe isolated, tool-free title invocation yet.
    case "cursor": return;
    case "opencode":
      return { args: [
        "run", "--pure", "--format", "json", "--agent", "detach-title",
        "--title", "Detach conversation naming", ...selected, prompt,
      ], env: {
        OPENCODE_DISABLE_AUTOUPDATE: "true",
        OPENCODE_CONFIG_CONTENT: JSON.stringify({
          autoupdate: false, share: "disabled", permission: { "*": "deny" },
          agent: { "detach-title": {
            mode: "primary", prompt: TITLE_INSTRUCTIONS, tools: { "*": false },
            permission: { "*": "deny" }, steps: 1,
          } },
        }),
      } };
    // fx supplies session_info_update from its own lightweight title generator.
    case "fx": return;
  }
}

export const AMP_TITLE_SETTINGS = {
  "amp.tools.disable": ["*"],
  "amp.mcpServers": {},
  "amp.mcpPermissions": [
    { matches: { command: "*" }, action: "reject" },
    { matches: { url: "*" }, action: "reject" },
  ],
  "amp.updates.mode": "disabled",
  "amp.notifications.enabled": false,
  "amp.skills.disableClaudeCodeSkills": true,
  "amp.skills.disableGlobalAgentsSkills": true,
};
