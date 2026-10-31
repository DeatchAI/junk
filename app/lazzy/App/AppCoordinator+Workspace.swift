import AppKit
import Combine
import SwiftUI

extension AppCoordinator {
  func setupBindings() {
    // New Floating Chat (configured by the user)
    hotkeyManager.onFloatingChatTriggered = { [weak self] in
      self?.openNewFloatingTask()
    }

    hotkeyManager.onCloseComposerTriggered = { [weak self] in
      self?.floatingWorkspace.dismissFrontmostTask()
    }

    // Resume the user's most recently active floating task.
    hotkeyManager.onResumeLastChatTriggered = { [weak self] in
      self?.resumeLastFloatingTask()
    }

    // History Panel
    hotkeyManager.onHistoryTriggered = { [weak self] in
      self?.toggleHistoryPanel()
    }

  }

  func setupActivityIslandCallbacks() {
    activityIsland.onOpenConversation = { [weak self] conversationId in
      guard let self, self.requireAppAccess() else { return }
      let location = NSEvent.mouseLocation
      if self.floatingWorkspace.showExistingTask(for: conversationId, at: location) {
        self.detachedRunStore.markReviewed(conversationId: conversationId)
      } else if let machineID = RemoteConversationIndex.shared.machineID(for: conversationId),
        RemoteMachineStore.shared.machine(id: machineID) != nil
      {
        self.openRemoteConversation(conversationId, machineID: machineID, at: location)
      } else {
        self.floatingWorkspace.openConversation(conversationId, at: location)
      }
    }

    activityIsland.onApprovalResponse = { [weak self] requestId, approved in
      _ = self?.respondToApproval(requestId: requestId, approved: approved)
    }

    observeRunEvents(on: wsManager)
  }

  /// Local and paired-phone decisions share the exact pending request and socket owner.
  @discardableResult
  func respondToApproval(requestId: String, approved: Bool) -> Bool {
    guard let manager = approvalManagers[requestId], manager.isConnected,
      detachedRunStore.runs.contains(where: { $0.state == .awaitingApproval && $0.approval?.id == requestId })
      else { return false }
    approvalManagers.removeValue(forKey: requestId)
    manager.sendCommandApprovalResponse(requestId: requestId, approved: approved)
    return true
  }

  func configureFloatingWorkspace() {
    floatingWorkspace.configureTask = { [weak self] task in
      guard let self else { return }
      task.controller.onToggleHistory = { [weak self, weak task] in
        guard let self, let task else { return }
        guard task.wsManager.remoteEndpoint != nil else { self.historyWindow.toggle(); return }
        let key = ObjectIdentifier(task.wsManager)
        let history: HistoryWindowController
        if let existing = self.remoteHistoryWindows[key] {
          history = existing
        } else {
          history = HistoryWindowController()
          history.wsManager = task.wsManager
          let machineID = task.wsManager.remoteEndpoint?.machineID
          history.onSelectConversation = { [weak self] conversation in
            guard let self, let machineID else { return }
            if self.floatingWorkspace.showExistingTask(for: conversation.id, at: NSEvent.mouseLocation) { return }
            self.openRemoteConversation(conversation.id, machineID: machineID, at: NSEvent.mouseLocation)
          }
          self.remoteHistoryWindows[key] = history
        }
        history.toggle()
      }
      task.controller.onHistoryRefresh = { [weak self, weak task] in
        guard let task else { return }
        if task.wsManager.remoteEndpoint != nil {
          task.wsManager.listConversations()
        } else {
          self?.wsManager.listConversations()
        }
      }
      task.controller.onNewChat = { [weak task] in
        task?.wsManager.startNewConversation()
      }
      let previousFrontmostCallback = task.controller.onFrontmostStateChanged
      task.controller.onFrontmostStateChanged = { [weak self, weak task] in
        previousFrontmostCallback?()
        guard let self, let task, task.controller.isFrontmost, !task.wsManager.isStreaming,
          !task.wsManager.currentResponse.isEmpty, let id = task.wsManager.currentConversationId else { return }
        self.detachedRunStore.markReviewed(conversationId: id)
      }
      // Voice mode is intentionally disabled until its UX pass is complete.
      if FeatureFlags.voiceModeEnabled {
        task.controller.onVoiceInputBegan = { [weak self, weak task] in
          guard let self, let task else { return }
          self.beginVoiceDictation(in: task.controller)
        }
        task.controller.onVoiceInputEnded = { [weak self] in
          self?.voiceDictation.endPushToTalk()
        }
        task.controller.onVoiceInputToggled = { [weak self, weak task] in
          guard let self, let task else { return }
          self.toggleVoiceDictation(in: task.controller)
        }
        task.controller.onVoiceInputCancelled = { [weak self, weak task] in
          guard let self, let task, self.voiceTargetController === task.controller else { return }
          self.voiceDictation.stop()
          self.voiceTargetController = nil
        }
      }
      task.controller.onDismissTransition = { [weak self] in
        self?.activityIsland.beginComposerHandoff()
      }
    }

    floatingWorkspace.onTaskCreated = { [weak self] task in
      self?.observeRunEvents(on: task.wsManager)
    }
  }

  func setupVoiceDictation() {
    guard FeatureFlags.voiceModeEnabled else { return }

    voiceDictation.onStateChanged = { [weak self] state, partialTranscript in
      self?.voiceTargetController?.updateVoiceDictation(
        state: state,
        partialTranscript: partialTranscript
      )
    }

    voiceDictation.onTranscription = { [weak self] transcript in
      self?.voiceTargetController?.insertVoiceTranscription(transcript)
    }
  }

  private func beginVoiceDictation(in controller: FloatingWindowController) {
    guard FeatureFlags.voiceModeEnabled else { return }
    voiceTargetController = controller
    voiceDictation.beginPushToTalk()
  }

  private func toggleVoiceDictation(in controller: FloatingWindowController) {
    guard FeatureFlags.voiceModeEnabled else { return }
    switch voiceDictation.state {
    case .idle, .failed:
      beginVoiceDictation(in: controller)
    case .requestingPermission, .listening, .processing:
      voiceDictation.endPushToTalk()
    }
  }

  private func observeRunEvents(on manager: WebSocketManager) {
    manager.addConversationLoadedListener { [weak self, weak manager] conversation, _ in
      guard let self, let manager,
        self.floatingWorkspace.tasks.contains(where: { $0.wsManager === manager && $0.controller.isFrontmost }) else { return }
      self.detachedRunStore.markReviewed(conversationId: conversation.id)
    }
    manager.onConversationTitleUpdated = { [weak self] conversationId, title in
      self?.detachedRunStore.updateConversationTitle(conversationId: conversationId, title: title)
      AgentQuestionCenter.shared.updateConversationTitle(conversationId: conversationId, title: title)
    }
    manager.onRunConnectionLost = { [weak self] runId, message in
      self?.detachedRunStore.connectionLost(runId: runId, message: message)
      self?.activityIsland.show()
    }
    manager.onRunStopRequested = { [weak self] runId in
      self?.detachedRunStore.requestStop(runId: runId)
      self?.activityIsland.show()
    }
    manager.addChatSentListener { [weak self, weak manager] request in
      guard let self, let manager else { return }
      self.detachedRunControls.register(request, manager: manager)
      self.detachedRunStore.begin(request, conversationTitle: manager.currentConversationTitle)
      self.activityIsland.show()
    }

    manager.addAgentActivityListener { [weak self] update in
      guard let self = self else { return }
      self.detachedRunStore.apply(update)
      self.activityIsland.show()
    }

    manager.addRunCompletionListener { [weak self, weak manager] runId, conversationId in
      guard let self else { return }
      MessagesRemoteController.shared.recordResult(runID: runId ?? manager?.activeChatRequest?.runId,
        text: manager?.currentResponse ?? "")
      self.detachedRunStore.complete(runId: runId, conversationId: conversationId)
      if let manager, !manager.currentResponse.isEmpty,
        self.detachedRunStore.runs.contains(where: { $0.id == runId && $0.state == .completed && !$0.isDebugPreview }),
        let agent = manager.activeChatRequest?.agent {
        AgentSetupModel.recordSuccessfulResponse(agent: agent)
      }
      if let manager, self.floatingWorkspace.tasks.contains(where: { $0.wsManager === manager && $0.controller.isFrontmost }) {
        self.detachedRunStore.markReviewed(conversationId: conversationId)
      }
      if !self.detachedRunStore.hasActiveRuns {
        self.activityIsland.showCompletion()
      }
    }

    manager.addRunErrorListener { [weak self] runId, message in
      guard let self else { return }
      self.detachedRunStore.fail(runId: runId, message: message)
      self.activityIsland.show()
    }

    manager.onCommandApprovalRequest = { [weak self, weak manager] id, runId, conversationId, command, description, riskLevel in
      guard let self, let manager else { return }
      DispatchQueue.main.async {
        self.approvalManagers[id] = manager
        self.detachedRunStore.requestApproval(
          id: id,
          runId: runId ?? manager.activeChatRequest?.runId,
          conversationId: conversationId,
          command: command,
          description: description,
          riskLevel: riskLevel
        )
        self.activityIsland.showApproval()
      }
    }

    manager.onCommandApprovalResolved = { [weak self] id, outcome in
      self?.approvalManagers.removeValue(forKey: id)
      let status: String
      switch outcome {
      case "approved": status = "Continuing agent task"
      case "declined": status = "Access declined"
      case "timed_out": status = "Approval request timed out"
      case "connection_lost": status = "Approval connection lost"
      default: status = "Approval cancelled"
      }
      self?.detachedRunStore.resolveApproval(id: id, status: status)
    }

    manager.onSecretCredentialRequest = { [weak self, weak manager] id, runId, conversationId, label, origin in
      guard let self else { return }
      self.detachedRunStore.requestCredential(id: id, runId: runId ?? manager?.activeChatRequest?.runId,
        conversationId: conversationId, label: label, origin: origin)
      self.activityIsland.showApproval()
    }

    manager.onSecretCredentialResolved = { [weak self] id, success in
      self?.detachedRunStore.resolveCredential(id: id, success: success)
      self?.activityIsland.show()
    }
  }
}
