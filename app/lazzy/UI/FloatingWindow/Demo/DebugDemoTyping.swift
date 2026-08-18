#if DEBUG
import Foundation

enum DebugDemoTyping {
  static func start(
    scenario: DebugDemoScenario,
    setMenuStep: @escaping (DebugComposerMenuStep) -> Void,
    appendCharacter: @escaping (Character) -> Void
  ) -> Task<Void, Never> {
    Task { @MainActor in
      setMenuStep(.showAttachmentMenu)
      guard await pause(milliseconds: 850) else { return }

      for mcpID in scenario.mcpServerIDs {
        setMenuStep(.selectMCP(mcpID))
        guard await pause(milliseconds: 520) else { return }
      }

      for fixturePath in scenario.fixturePaths {
        guard let url = DebugDemoFixtures.url(for: fixturePath) else { continue }
        setMenuStep(.selectFile(url))
        guard await pause(milliseconds: 360) else { return }
      }

      setMenuStep(.dismissAttachmentMenu)
      guard await pause(milliseconds: 300) else { return }
      setMenuStep(.showCommandMenu)
      guard await pause(milliseconds: 850) else { return }
      setMenuStep(.selectCommand(scenario.commandID))
      guard await pause(milliseconds: 600) else { return }

      for character in scenario.prompt {
        guard !Task.isCancelled else { return }
        appendCharacter(character)
        try? await Task.sleep(for: .milliseconds(18))
      }
    }
  }

  private static func pause(milliseconds: Int) async -> Bool {
    do {
      try await Task.sleep(for: .milliseconds(milliseconds))
      return !Task.isCancelled
    } catch {
      return false
    }
  }
}
#endif
