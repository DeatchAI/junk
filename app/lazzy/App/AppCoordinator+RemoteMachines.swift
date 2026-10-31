import AppKit

extension AppCoordinator {
  func openRemoteConversation(_ conversationID: String, machineID: UUID, at location: NSPoint) {
    guard let selection = RemoteMachineStore.shared.firstWorkspaceSelection(machineID: machineID) else {
      showRemoteReconnectError("Add a remote folder for this machine before reopening its conversations.")
      return
    }

    Task { @MainActor in
      do {
        let endpoint = try await RemoteMachineRuntimeConnector.shared.connect(to: selection)
        _ = floatingWorkspace.openNewTask(
          at: location, conversationId: conversationID, centered: true, runtimeEndpoint: endpoint
        )
      } catch {
        showRemoteReconnectError(error.localizedDescription)
      }
    }
  }

  private func showRemoteReconnectError(_ detail: String) {
    let alert = NSAlert()
    alert.messageText = "Could not reconnect to the remote conversation"
    alert.informativeText = detail
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
