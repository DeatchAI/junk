import Foundation

/// One visible action in the Debug-only composer walkthrough.
enum DebugComposerMenuStep: Equatable {
  case showAttachmentMenu
  case selectMCP(String)
  case selectFile(URL)
  case dismissAttachmentMenu
  case showCommandMenu
  case selectCommand(String)
  case dismissCommandMenu
}
