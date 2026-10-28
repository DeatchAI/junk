import { type ServerWebSocket, activeRuns, agentQuestions, desktopBridge, secretBridge, agents, savedWorkflows, slashCommands, composio, mcpServers, tools } from "./RuntimeContext";
import { type ClientMessage } from "../protocol/messages";
import { send, capabilities } from "./RuntimeHelpers";
import { handleChat } from "./ProviderChat";
import { resolvePermissionsForSocket, resolveAgentPermission } from "./RuntimeApprovals";
import { statusForServer } from "../history/SqliteMCPServers";
import { handleProviderHistory } from "./ProviderHistory";


export async function handleMessage(ws: ServerWebSocket, raw: string) {
  let message: ClientMessage;

  try {
    message = JSON.parse(raw);
  } catch {
    send(ws, { type: "error", error: "Invalid message format" });
    return;
  }

  try {
    if (await handleProviderHistory(ws, message)) return;
    switch (message.type) {
      case "ping":
        send(ws, { type: "pong" });
        return;

      case "capabilities":
        send(ws, await capabilities());
        return;

      case "chat":
        await handleChat(ws, message);
        return;

      case "stop_stream":
        activeRuns.get(ws)?.cancel();
        activeRuns.delete(ws);
        resolvePermissionsForSocket(ws, false, "cancelled");
        agentQuestions.endSocket(ws);
        send(ws, { type: "activity", activityStatus: "Stopped" });
        return;

      case "command_approval_response":
        resolveAgentPermission(message.requestId, message.approved);
        return;

      case "agent_question_response":
        if (agentQuestions.respond(ws, message) && message.cancelled === true) {
          activeRuns.get(ws)?.cancel();
          agentQuestions.endSocket(ws);
        }
        return;

      case "desktop_command_result":
        desktopBridge.handleResult(message);
        return;

      case "secret_command_result":
        secretBridge.handleResult(message);
        return;

      case "update_ai_settings":
        if (message.agent && agents.has(message.agent)) {
          agents.setCurrentAgent(message.agent);
        }
        return;

      case "list_workflows":
        send(ws, { type: "workflows_list", workflows: savedWorkflows.list("workflow") });
        return;

      case "add_workflow": {
        const workflow = savedWorkflows.add({
          ...message,
          kind: "workflow",
          trigger: "manual",
          inputPolicy: message.inputPolicy ?? "none",
          executionMode: message.executionMode ?? "run_immediately",
        });
        send(ws, { type: "workflow_added", workflow });
        return;
      }

      case "update_workflow": {
        if (savedWorkflows.get(message.actionId)?.kind !== "workflow") {
          send(ws, { type: "error", error: "Workflow not found" });
          return;
        }
        const workflow = savedWorkflows.update(message.actionId, {
          name: message.name,
          prompt: message.prompt,
          systemImage: message.systemImage,
          shortcut: message.shortcut,
          enabled: message.enabled,
          position: message.position,
          mcpServerIds: message.mcpServerIds,
          skills: message.skills,
          inputPolicy: message.inputPolicy,
          executionMode: message.executionMode,
        });
        if (!workflow) {
          send(ws, { type: "error", error: "Workflow not found" });
          return;
        }
        send(ws, { type: "workflow_updated", workflow });
        return;
      }

      case "delete_workflow":
        if (savedWorkflows.get(message.actionId)?.kind !== "workflow") {
          send(ws, { type: "error", error: "Workflow not found" });
          return;
        }
        savedWorkflows.delete(message.actionId);
        send(ws, { type: "workflow_deleted", actionId: message.actionId });
        return;

      case "list_slash_commands":
        send(ws, { type: "slash_commands_list", commands: slashCommands.list() });
        return;

      case "add_slash_command": {
        const command = slashCommands.add({
          command: message.command,
          title: message.title,
          subtitle: message.subtitle,
          systemImage: message.systemImage,
          replacementText: message.replacementText,
          promptInstruction: message.promptInstruction,
          mode: message.mode,
        });
        send(ws, { type: "slash_command_added", command });
        return;
      }

      case "update_slash_command": {
        const command = slashCommands.update(message.commandId, {
          command: message.command,
          title: message.title,
          subtitle: message.subtitle,
          systemImage: message.systemImage,
          replacementText: message.replacementText,
          promptInstruction: message.promptInstruction,
          mode: message.mode,
          enabled: message.enabled,
          position: message.position,
        });
        if (!command) {
          send(ws, { type: "error", error: "Slash command not found" });
          return;
        }
        send(ws, { type: "slash_command_updated", command });
        return;
      }

      case "delete_slash_command":
        slashCommands.delete(message.commandId);
        send(ws, { type: "slash_command_deleted", commandId: message.commandId });
        return;

      case "list_mcp_servers":
        await composio.refreshAccess();
        send(ws, {
          type: "mcp_servers_list",
          servers: mcpServers.listWithStatus().filter(
            (server) => server.name !== "Composio MCP" || composio.isAccessAllowed(),
          ),
        });
        return;

      case "add_mcp_server": {
        const server = mcpServers.add({
          name: message.name,
          transport: message.transport,
          command: message.command,
          args: message.args,
          url: message.url,
          headers: message.headers,
          env: message.env,
          enabled: message.enabled ?? true,
        });
        send(ws, { type: "mcp_server_added", server, status: statusForServer(server) });
        return;
      }

      case "update_mcp_server": {
        const server = mcpServers.update(message.serverId, {
          name: message.name,
          transport: message.transport,
          command: message.command,
          args: message.args,
          url: message.url,
          headers: message.headers,
          env: message.env,
          enabled: message.enabled,
        });
        if (!server) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_updated", server });
        return;
      }

      case "delete_mcp_server":
        if (!mcpServers.delete(message.serverId)) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_deleted", serverId: message.serverId });
        return;

      case "connect_mcp_server": {
        const server = mcpServers.update(message.serverId, { enabled: true });
        if (!server) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_connected", status: statusForServer(server) });
        return;
      }

      case "disconnect_mcp_server": {
        const server = mcpServers.update(message.serverId, { enabled: false });
        if (!server) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_disconnected", serverId: message.serverId });
        return;
      }

      case "list_mcp_tools":
        send(ws, {
          type: "mcp_tools_list",
          tools: [
            ...tools.summary().tools.map((name) => ({ name })),
            ...mcpServers.listEnabled().map((server) => ({
              name: server.name,
              description: `${server.transport.toUpperCase()} MCP server`,
            })),
          ],
        });
        return;

      case "list_composio_integrations":
        send(ws, await composio.listIntegrations({
          limit: message.limit,
          offset: message.offset,
          query: message.query,
          userId: message.userId,
        }));
        return;

      case "connect_composio_account": {
        const result = await composio.connectToolkit({
          toolkit: message.toolkit,
          userId: message.userId,
          callbackUrl: message.callbackUrl,
        });
        for (const response of result.messages) send(ws, response);
        if (result.pending) {
          result.pending
            .then((responses) => {
              for (const response of responses) send(ws, response);
            })
            .catch((error) => {
              send(ws, {
                type: "error",
                error: error instanceof Error ? error.message : String(error),
              });
            });
        }
        return;
      }

      case "list_composio_connections":
        send(ws, { type: "composio_connections", connections: await composio.listConnections({ userId: message.userId }) });
        return;

      case "disconnect_composio_account":
        await composio.disconnect(message.connectionId, message.userId);
        send(ws, { type: "composio_disconnected", connectionId: message.connectionId });
        return;

      default: {
        const unknownMessage = message as { type: string };
        send(ws, { type: "error", error: `Detach runtime does not handle '${unknownMessage.type}' yet.` });
      }
    }
  } catch (error) {
    send(ws, { type: "error", error: error instanceof Error ? error.message : String(error) });
  }
}
