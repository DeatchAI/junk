import type { AgentStreamCallbacks } from "../AgentAdapter";
import { asStringRecord as record, getString } from "../CliAdapterUtils";

export async function codexApprovalResponse(
  method: string,
  params: Record<string, unknown>,
  callbacks: AgentStreamCallbacks,
  item?: Record<string, unknown>,
) {
  switch (method) {
    case "item/commandExecution/requestApproval": {
      const network = record(params.networkApprovalContext);
      const command = getString(params.command) || getString(item?.command);
      const title = network ? `Connect to ${getString(network.host) || "network"}` : "Run command";
      const approved = await approve(callbacks, title, [
        getString(params.reason),
        network ? `Network destination: ${JSON.stringify(network)}` : undefined,
        command,
        getString(params.cwd) ? `Working folder: ${params.cwd}` : undefined,
      ], command || title);
      return { decision: approved ? "accept" : "decline" };
    }
    case "item/fileChange/requestApproval": {
      const changes = Array.isArray(item?.changes) ? item.changes : [];
      const approved = await approve(callbacks, "Allow file changes", [
        getString(params.reason),
        getString(params.grantRoot) ? `Requested folder: ${params.grantRoot}` : undefined,
        ...changes.map((change) => getString(record(change)?.path)),
      ]);
      return { decision: approved ? "accept" : "decline" };
    }
    case "item/permissions/requestApproval": {
      const permissions = record(params.permissions) ?? {};
      const approved = await approve(callbacks, "Allow additional access", [
        getString(params.reason),
        getString(params.cwd) ? `Working folder: ${params.cwd}` : undefined,
        JSON.stringify(permissions, null, 2),
      ]);
      // Grant only the requested permissions, and only for this turn.
      return { permissions: approved ? permissions : {}, scope: "turn" };
    }
    case "mcpServer/elicitation/request": {
      const schema = record(params.requestedSchema);
      const properties = record(schema?.properties);
      const required = Array.isArray(schema?.required) ? schema.required : [];
      // A yes/no UI cannot supply form fields or complete an external login.
      if (params.mode !== "form" || required.length || Object.keys(properties ?? {}).length) {
        return { action: "decline", content: null };
      }
      const approved = await approve(callbacks, "Allow tool request", [getString(params.message)]);
      return { action: approved ? "accept" : "decline", content: approved ? {} : null };
    }
    default:
      return undefined;
  }
}

async function approve(
  callbacks: AgentStreamCallbacks,
  title: string,
  details: Array<string | undefined>,
  toolName = title,
) {
  if (!callbacks.onPermission) return false;
  return await callbacks.onPermission({
      title,
      description: details.filter(Boolean).join("\n\n") || title,
      riskLevel: "normal",
      toolName,
  }) === true;
}
