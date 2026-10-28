import type { ChatRequest, MCPServerConfig } from "../../protocol/messages";
import { codexMCPArgs } from "./CodexMCPConfig";
import { codexAdditionalContext } from "./CodexPrompt";

export function buildCodexAppServerArgs(servers: MCPServerConfig[] = []) {
  return [
    "app-server",
    "-c", 'features.default_mode_request_user_input=true',
    ...codexMCPArgs(servers),
  ];
}

export function buildCodexThreadParams(request: ChatRequest, cwd: string) {
  return {
    cwd,
    model: request.model?.trim() || undefined,
    ephemeral: false,
    sandbox: request.permissionMode && request.permissionMode !== "native" ? "workspace-write" : undefined,
    ...codexPermissions(request),
    serviceName: "detach",
  };
}

export function buildCodexTurnParams(request: ChatRequest, cwd: string, threadId: string, prompt: string) {
  const effort = request.modelSettings?.reasoningEffort?.trim();
  return {
    threadId,
    cwd,
    input: [
      { type: "text", text: prompt, text_elements: [] },
      ...imageAttachmentPaths(request.files).map((path) => ({ type: "localImage", path })),
    ],
    model: request.model?.trim() || undefined,
    effort: effort && ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].includes(effort)
      ? effort : undefined,
    additionalContext: codexAdditionalContext(request),
    ...codexPermissions(request),
    sandboxPolicy: request.permissionMode && request.permissionMode !== "native" ? {
      type: "workspaceWrite",
      writableRoots: [cwd],
      networkAccess: false,
      excludeTmpdirEnvVar: false,
      excludeSlashTmp: false,
    } : undefined,
  };
}

function codexPermissions(request: ChatRequest) {
  if (!request.permissionMode || request.permissionMode === "native") return {};
  return {
    approvalPolicy: "on-request",
    approvalsReviewer: request.permissionMode === "auto" ? "auto_review" : "user",
  };
}

export function imageAttachmentPaths(files: ChatRequest["files"] = []) {
  return files.filter((file) => file.path?.trim() && (
    file.mimeType?.toLowerCase().startsWith("image/")
    || /\.(png|jpe?g|gif|webp|heic|heif|tiff?|bmp)$/i.test(file.path)
  )).map((file) => file.path.trim());
}
