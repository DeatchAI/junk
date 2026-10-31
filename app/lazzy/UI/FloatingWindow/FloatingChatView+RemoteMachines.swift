import Foundation

extension FloatingChatView {
  func connectRemoteWorkspace(_ target: RemoteWorkspaceSelection?, forceReconnect: Bool = false) {
    remoteConnectionTask?.cancel()
    guard let target else {
      workingDirectoryStore.setRemoteConnectionStatus(.idle)
      if wsManager.remoteEndpoint != nil { wsManager.connect(to: .local) }
      return
    }

    workingDirectoryStore.setRemoteConnectionStatus(.connecting)
    remoteConnectionTask = Task { @MainActor in
      do {
        let endpoint = try await RemoteMachineRuntimeConnector.shared.connect(to: target, forceReconnect: forceReconnect)
        guard !Task.isCancelled, workingDirectoryStore.remoteWorkspace == target else { return }
        wsManager.connect(to: endpoint)
        if wsManager.isConnected { workingDirectoryStore.setRemoteConnectionStatus(.connected) }
      } catch {
        guard !Task.isCancelled, workingDirectoryStore.remoteWorkspace == target else { return }
        workingDirectoryStore.setRemoteConnectionStatus(.failed(error.localizedDescription))
      }
    }
  }

  func remoteSendIsReady() -> Bool {
    if workingDirectoryStore.isRemote && (!pendingAttachments.isEmpty || !pendingBrowserTabs.isEmpty) {
      errorMessage = "Remove local file and browser-tab attachments before sending to a remote machine. The agent can read files inside its remote folder."
      return false
    }
    guard workingDirectoryStore.isReady(on: wsManager.runtimeEndpoint) else {
      errorMessage = workingDirectoryStore.remoteConnectionStatus == .connecting
        ? "Connecting to the remote machine. Try again in a moment."
        : "Reconnect to the remote machine before starting this task."
      return false
    }
    return true
  }
}
