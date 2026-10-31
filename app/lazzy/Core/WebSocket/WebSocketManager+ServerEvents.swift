import AppKit
import Foundation
import Combine

extension WebSocketManager {
  func handleServerMessage(_ message: ServerMessage) {
    switch message {
    case .chunk(let text, let isFirst, let timeToFirstChunkMs):
      currentResponse += text
      onChunk?(text)
      if isFirst, let ttfc = timeToFirstChunkMs {
        onFirstChunk?(ttfc)
      }

    case .done(let runId, let conversationId, let messageId, let userMessageId, let tokenCount, let durationMs):
      dismissAgentQuestions()
      isStoppingRun = false
      isStreaming = false
      // Store the conversation ID for follow-up messages
      currentConversationId = conversationId
      onComplete?(conversationId, messageId, userMessageId, tokenCount, durationMs)
      completionListeners.forEach {
        $0(conversationId, messageId, userMessageId, tokenCount, durationMs)
      }
      runCompletionListeners.forEach { $0(runId ?? activeChatRequest?.runId, conversationId) }
      print(
        "✅ Response complete (conversation: \(conversationId), tokens: \(tokenCount ?? 0), duration: \(durationMs ?? 0)ms)"
      )

    case .error(let errorMessage, let runId):
      isStoppingRun = false
      cancelAutoRouting()
      isLoadingMoreConversations = false
      dismissAgentQuestions()
      lastError = errorMessage
      composioError = errorMessage
      connectingToolkit = nil
      isLoadingMCPServers = false
      isStreaming = false
      onError?(errorMessage)
      errorListeners.forEach { $0(errorMessage) }
      runErrorListeners.forEach { $0(runId ?? activeChatRequest?.runId, errorMessage) }

    case .pong:
      // Connection verified
      if !isConnected {
        isConnected = true
        print("✅ Connection verified via pong")
      }

    case .capabilities(let agents, let defaultAgent):
      capabilitiesTimeoutTask?.cancel()
      capabilitiesTimeoutTask = nil
      capabilitiesRequestInFlight = false
      let refreshAgain = capabilitiesRefreshQueued
      capabilitiesRefreshQueued = false
      isLoadingCapabilities = refreshAgain
      let agents = agents.filter { AgentProvider(rawValue: $0.id) != nil }
      agentCapabilities = agents
      AutoRouter.shared.capabilities = agents
      if let defaultAgent {
        self.defaultAgent = defaultAgent
      }
      if !agents.contains(where: { $0.id == DetachSettings.selectedAgent && $0.installed }),
        let firstInstalled = agents.first(where: { $0.installed })
      {
        DetachSettings.selectedAgent = firstInstalled.id
      }
      print("🧠 Agent capabilities loaded: \(agents.map { "\($0.displayName):\($0.installed)" }.joined(separator: ", "))")
      if refreshAgain {
        requestCapabilities()
      }

    case .conversationsList(let convs, let offset, let hasMore):
      if offset > 0 && offset != nextConversationOffset { return }
      if offset > 0 {
        let known = Set(conversations.map(\.id))
        conversations += conversationTitleCache.merging(convs.filter { !known.contains($0.id) })
      } else {
        conversations = conversationTitleCache.merging(convs)
      }
      nextConversationOffset = offset + convs.count
      hasMoreConversations = hasMore
      isLoadingMoreConversations = false
      if !isStreaming, let id = currentConversationId, let latest = conversations.first(where: { $0.id == id }) {
        let previous = currentConversationTitle
        currentConversation = latest; currentConversationTitle = latest.title
        if previous != latest.title, let title = latest.title { onConversationTitleUpdated?(id, title) }
      }
      onConversationsLoaded?(conversations)
      print("📚 Loaded \(convs.count) conversations")

    case .conversation(let conv, let messages):
      if isStreaming && currentConversationId == conv.id { return }
      currentConversationId = conv.id
      let named = conversationTitleCache.merging([conv]).first ?? conv
      currentConversationTitle = named.title
      currentConversation = named
      onConversationLoaded?(named, messages)
      conversationLoadedListeners.forEach { $0(named, messages) }
      print("💬 Loaded conversation with \(messages.count) messages")

    case .searchResults(let results):
      onSearchResults?(results)
      print("🔍 Found \(results.count) search results")

    case .deleted(let id):
      conversationTitleCache.remove(id)
      // Remove from local cache if it's a conversation
      conversations.removeAll { $0.id == id }
      // Clear current if deleted
      if currentConversationId == id {
        currentConversationId = nil
        currentConversation = nil
      }
      onDeleted?(id)
      print("🗑️ Deleted: \(id)")

    case .updated(let id):
      onUpdated?(id)
      print("✏️ Updated: \(id)")

    // MCP messages
    case .mcpServerAdded(let server):
      mcpServers.append(server)
      print("🔧 MCP server added: \(server.name)")
      listMCPServers()  // Refresh list

    case .mcpServersList(let servers):
      mcpServers = servers
      isLoadingMCPServers = false
      onMCPServersLoaded?(servers)
      print("🔧 Loaded \(servers.count) MCP servers")

    case .mcpServerDeleted(let serverId):
      mcpServers.removeAll { $0.id == serverId }
      print("🔧 MCP server deleted: \(serverId)")
      listMCPServers()

    case .mcpServerConnected(let status):
      if let index = mcpServers.firstIndex(where: { $0.id == status.id }) {
        mcpServers[index].status = status
      }
      print("🔧 MCP server connected: \(status.name)")
      listMCPServers()

    case .mcpServerDisconnected(let serverId):
      if let index = mcpServers.firstIndex(where: { $0.id == serverId }) {
        mcpServers[index].status = nil
      }
      print("🔧 MCP server disconnected: \(serverId)")
      listMCPServers()

    case .mcpToolsList(let tools):
      print("🔧 MCP tools: \(tools.map { $0.name })")

    case .mcpServerUpdated(let server):
      if let index = mcpServers.firstIndex(where: { $0.id == server.id }) {
        mcpServers[index] = server
      }
      print("🔧 MCP server updated: \(server.name)")
      listMCPServers()

    // Composio messages
    case .composioIntegrations(
      let configured, let integrations, let total, let hasMore, let limit, let offset, let error):
      isLoadingComposio = false
      composioError = error
      connectingToolkit = nil

      if (offset ?? 0) == 0 {
        composioIntegrations = integrations
      } else {
        // Append unique newcomers
        let existingIds = Set(composioIntegrations.map { $0.id })
        let uniqueNew = integrations.filter { !existingIds.contains($0.id) }
        composioIntegrations.append(contentsOf: uniqueNew)
      }

      self.totalComposioIntegrations = total ?? 0
      self.hasMoreComposioIntegrations = hasMore ?? false

      onComposioIntegrations?(configured, integrations, total, hasMore, limit, offset, error)
      print(
        "🔌 Composio integrations: \(integrations.count) available, total: \(total ?? 0), hasMore: \(hasMore ?? false)"
      )

    case .composioAuthUrl(let url, let toolkit, let connectionId):
      if let authUrl = URL(string: url) {
        #if os(macOS)
          NSWorkspace.shared.open(authUrl)
          print("🌐 Opened auth URL for \(toolkit)")
        #endif
      }
      onComposioAuthUrl?(url, toolkit, connectionId)
      print("🔌 Composio auth URL for \(toolkit)")

    case .composioConnections(let connections):
      onComposioConnections?(connections)
      print("🔌 Composio connections: \(connections.count)")

    case .composioConnected(let toolkit, let connectionId, let status):
      connectingToolkit = nil
      listComposioIntegrations()  // Refresh the whole list to show "Connected" status
      onComposioConnected?(toolkit, connectionId, status)
      print("✅ Composio connected: \(toolkit) (\(connectionId))")

    case .composioDisconnected(let connectionId):
      listComposioIntegrations()  // Refresh to show "Available"
      onComposioDisconnected?(connectionId)
      print("🔌 Composio disconnected: \(connectionId)")

    case .actionLearningStarted(_, let actionName):
      let name = actionName.isEmpty ? "this action" : actionName
      publishActivity("Learning \(name) for faster future runs", toolName: "Action learning")
      print("🧠 Learning action: \(name)")

    case .actionLearningCompleted(let action):
      if action.kind == "workflow" {
        if let index = workflows.firstIndex(where: { $0.id == action.id }) {
          workflows[index] = action
        }
        onWorkflowUpdated?(action)
      }
      print("🧠 Learned action skill: \(action.title)")

    case .workflowsList(let items):
      workflows = items
      onWorkflowsList?(items)
      print("⚙️ Loaded \(items.count) workflows")

    case .workflowAdded(let workflow):
      workflows.append(workflow)
      onWorkflowAdded?(workflow)
      print("⚙️ Workflow added: \(workflow.title)")

    case .workflowUpdated(let workflow):
      if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
        workflows[index] = workflow
      }
      onWorkflowUpdated?(workflow)
      print("⚙️ Workflow updated: \(workflow.title)")

    case .workflowDeleted(let actionId):
      workflows.removeAll { $0.id == actionId }
      onWorkflowDeleted?(actionId)
      print("⚙️ Workflow deleted: \(actionId)")

    case .slashCommandsList(let commands):
      customSlashCommands = commands
      onSlashCommandsList?(commands)
      print("⌨️ Loaded \(commands.count) custom slash commands")

    case .slashCommandAdded(let command):
      customSlashCommands.append(command)
      onSlashCommandAdded?(command)
      print("⌨️ Custom slash command added: \(command.command)")

    case .slashCommandUpdated(let command):
      if let index = customSlashCommands.firstIndex(where: { $0.id == command.id }) {
        customSlashCommands[index] = command
      }
      onSlashCommandUpdated?(command)
      print("⌨️ Custom slash command updated: \(command.command)")

    case .slashCommandDeleted(let commandId):
      customSlashCommands.removeAll { $0.id == commandId }
      onSlashCommandDeleted?(commandId)
      print("⌨️ Custom slash command deleted: \(commandId)")

    case .unknown:
      print("⚠️ Received unknown message type")

    case .contextSummary(let summary):
      guard summary.runId == activeChatRequest?.runId else { return }
      lastContextSummary = summary

    case .commandApprovalResolved(let id, let outcome):
      onCommandApprovalResolved?(id, outcome)

    case .activity(let status, let toolName, let event, let runId, let conversationId):
      publishActivity(status, toolName: toolName, event: event, runId: runId, conversationId: conversationId)

    case .commandApprovalRequest(let id, let runId, let conversationId, let command, let description, let riskLevel):
      onCommandApprovalRequest?(id, runId, conversationId, command, description, riskLevel)
      print("⚠️ Command approval request: \(command) (risk: \(riskLevel))")

    case .secretCommand(let id, let command, let credentialId, let query, let origin, _, _, let runId, let conversationId):
      Task { @MainActor [weak self] in
        await self?.handleSecretCommand(id: id, command: command, credentialId: credentialId, query: query, origin: origin, runId: runId, conversationId: conversationId)
      }
    }
  }

}
