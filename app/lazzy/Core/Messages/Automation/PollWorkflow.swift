import AppKit
import ApplicationServices

/// Drives the visible Messages UI through accessibility roles and current frames.
@MainActor
final class PollWorkflow {
  let ax: PollAccessibility
  let recipient: String
  private let navigate: Bool
  private var ownedDraft: PollDraft?
  private(set) var phase = "Preparing poll"
  var trace: (String) -> Void = { _ in }

  init(recipient: String, navigate: Bool = false) throws {
    self.recipient = recipient
    self.navigate = navigate
    ax = try PollAccessibility()
  }

  func composer() throws -> AXUIElement {
    let nodes = try ax.controls()
    let identified = nodes.filter { ax.string($0, kAXIdentifierAttribute) == "messageBodyField" }
    if identified.count == 1 { return identified[0] }
    guard identified.isEmpty else {
      throw PollUIError.unavailable("Messages exposes multiple composer fields. No action taken.")
    }
    return try ax.unique(nodes, description: "message composer") {
      self.ax.isMessageComposer($0)
    }
  }

  func pollFields() throws -> [AXUIElement] {
    let polls = try ax.controls().filter {
      ax.string($0, kAXRoleAttribute) == kAXGroupRole && ax.string($0, kAXDescriptionAttribute) == "Poll"
    }
    guard polls.count <= 1 else { throw PollUIError.unavailable("Multiple draft polls are visible.") }
    guard let poll = polls.first else { return [] }
    return ax.descendants(poll).filter {
      [kAXTextAreaRole, kAXTextFieldRole].contains(ax.string($0, kAXRoleAttribute))
    }
  }

  func draft() throws -> PollDraft {
    let nodes = try ax.controls()
    let fields = try pollFields()
    let attached = !fields.isEmpty || nodes.contains {
      ax.string($0, kAXDescriptionAttribute) == "Remove app from message"
    }
    return PollDraft(comment: ax.string(try composer(), kAXValueAttribute),
      options: fields.map { ax.string($0, kAXValueAttribute) }.filter { !$0.isEmpty },
      hasAttachment: attached)
  }

  private func detailsAreOpen() throws -> Bool {
    try ax.controls().contains { ax.string($0, kAXIdentifierAttribute) == "DetailsHeaderTitle" }
  }

  private func setDetails(open: Bool) async throws {
    guard try detailsAreOpen() != open else { return }
    func control() throws -> AXUIElement {
      let nodes = try ax.controls()
      if !open { return try ax.button("Close", in: nodes) }
      return try ax.unique(nodes, description: "conversation details button") {
        self.ax.string($0, kAXIdentifierAttribute) == "ConversationTitle" &&
          self.ax.string($0, kAXRoleAttribute) == kAXButtonRole
      }
    }
    // One live-frame action per transition. Repeating a toggle after an
    // acknowledged AXPress can close a panel that is still opening.
    trace(open ? "Opening recipient details once" : "Closing recipient details once")
    try await ax.click(control())
    try await ax.wait(open ? "conversation details" : "conversation details to close", stableFor: 0.35) {
      try self.detailsAreOpen() == open
    }
  }

  /// Verifies the RECENT address on the conversation card, never a contact's display name.
  func verifyRecipient() async throws {
    try await waitForConversation()
    let deadline = Date().addingTimeInterval(10)
    var lastTransitionError: Error?
    while Date() < deadline {
      try ax.checkpoint()
      var closeDetailsAfterAttempt = false
      do {
        let conversationWindow = try ax.window()
        try ax.pinWindow(conversationWindow)
        let detailsWereOpen = try detailsAreOpen()
        closeDetailsAfterAttempt = !detailsWereOpen
        try await setDetails(open: true)
        let addresses = try ax.controls().filter {
          ax.string($0, kAXIdentifierAttribute) == "ContactCardLabeledPropertyView"
        }
        let recent = addresses.filter { ax.string($0, kAXDescriptionAttribute).components(separatedBy: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains("RECENT") }
        let matched = recent.count == 1 &&
          PollRecipient.isRecentMatch(ax.string(recent[0], kAXDescriptionAttribute), recipient: recipient)
        if closeDetailsAfterAttempt { try await setDetails(open: false) }
        guard CFEqual(conversationWindow, try ax.window()) else {
          throw PollUIError.unavailable("The Messages conversation changed during recipient verification.")
        }
        if matched {
          verifiedWindow = conversationWindow
          verifiedTitle = ax.string(conversationWindow, kAXTitleAttribute)
          return
        }
        ax.unpinWindow()
      } catch {
        if closeDetailsAfterAttempt { try? await setDetails(open: false) }
        ax.unpinWindow()
        try ax.checkpoint()
        lastTransitionError = error
      }
      try await Task.sleep(nanoseconds: 250_000_000)
    }
    if let lastTransitionError {
      throw PollUIError.unavailable("Messages did not finish opening the paired conversation: \(lastTransitionError.localizedDescription)")
    }
    throw PollUIError.unavailable("This is not the paired phone's verified direct conversation. Open that conversation in Messages and retry.")
  }

  private func waitForConversation() async throws {
    try await ax.wait("the Messages conversation composer", seconds: 12,
      retryingTransientErrors: true) {
      _ = try self.composer()
      return true
    }
  }

  private var verifiedWindow: AXUIElement?
  private var verifiedTitle: String?

  private func verifySameWindow() throws {
    try ax.checkpoint()
    let window = try ax.window()
    guard let previous = verifiedWindow, CFEqual(previous, window),
      ax.string(window, kAXTitleAttribute) == verifiedTitle else {
      throw PollUIError.unavailable("The Messages conversation changed during this run.")
    }
  }

  private func stage(_ message: String) {
    phase = message
    trace(message)
    FileHandle.standardError.write(Data("[poll] \(message)\n".utf8))
  }

  func prepare(_ request: PollRequest) async throws {
    try request.validate()
    try await ax.activate()
    if navigate {
      let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@+.-_"))
      guard let address = recipient.addingPercentEncoding(withAllowedCharacters: safe),
        let url = URL(string: "sms:\(address)"), NSWorkspace.shared.open(url) else {
        throw PollUIError.unavailable("Could not open the paired conversation in Messages.")
      }
    }
    stage("Verifying paired recipient")
    try await verifyRecipient()
    let existing = try draft()
    let fields = try pollFields()
    guard existing.matches(request) ||
      existing.comment.isEmpty && existing.options.isEmpty && (!existing.hasAttachment || !fields.isEmpty) else {
      throw PollUIError.unavailable("There is already a draft or attachment. It was left untouched.")
    }
    if existing.matches(request) { ownedDraft = existing }
    if fields.isEmpty {
      stage("Opening Polls")
      try await ax.click(ax.button("add"))
      try await ax.wait("Polls menu") { !self.pollMenuItems().isEmpty }
      let items = pollMenuItems()
      guard items.count == 1 else { throw PollUIError.unavailable("Polls menu is ambiguous.") }
      try ax.press(items[0])
      try await ax.wait("poll choices") { try self.pollFields().count >= 2 }
      ownedDraft = try draft()
    }
    for (index, option) in request.options.enumerated() {
      try verifySameWindow()
      stage("Entering choice \(index + 1)")
      var current = try pollFields()
      if index >= current.count {
        try await ax.focus(resolving: composer)
        try await ax.wait("another poll choice") { try self.pollFields().count > index }
        current = try pollFields()
      }
      guard index < current.count else {
        throw PollUIError.unavailable("Messages did not expose another poll choice. The partial draft was preserved.")
      }
      try await ax.type(option, resolving: {
        let refreshed = try self.pollFields()
        guard index < refreshed.count else {
          throw PollUIError.unavailable("Messages recreated a poll choice before it was ready.")
        }
        return refreshed[index]
      })
      ownedDraft = try draft()
      // The next field commits this choice; avoid bouncing through the resizing composer.
    }
    stage("Entering poll comment")
    try verifySameWindow()
    try await ax.type(request.question, resolving: composer)
    ownedDraft = try draft()
    try await ax.wait("verified poll draft") { try self.draft().matches(request) }
  }

  func sendPrepared(_ request: PollRequest, requestURL: URL) async throws -> [String: String] {
    try request.validate()
    try await ax.activate()
    if verifiedWindow == nil {
      stage("Verifying paired recipient")
      try await verifyRecipient()
    }
    try verifySameWindow()
    guard try draft().matches(request) else {
      throw PollUIError.unavailable("The draft changed or is missing. Run prepare first; nothing was sent.")
    }
    try await ax.focus(resolving: composer)
    // No automatic retry after this point, including timeout and process restart.
    let receipt = try PollSendAttempt.reserve(beside: requestURL, request: request)
    stage("Pressing Return in the verified composer")
    try await ax.key(36)
    try await ax.wait("poll draft to leave the composer", seconds: 6) {
      try self.draft().isEmpty
    }
    stage("Composer cleared")
    return ["status": "submitted", "request_id": request.id.uuidString,
      "receipt": receipt.path, "delivery": "Check the phone; submission does not prove delivery."]
  }

  /// Remove only the exact unsent draft this workflow created, while Messages
  /// is still active. A user's changed draft or interrupted desktop is untouched.
  func discardOwnedDraft() async -> Bool {
    guard let ownedDraft else { return (try? draft().isEmpty) == true }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ax.app.processIdentifier,
      !PollAccessibility.isScreenLocked else { return false }
    let pending = ax.canContinue
    ax.canContinue = { true }
    defer { ax.canContinue = pending }
    do {
      try verifySameWindow()
      guard try draft() == ownedDraft else { return false }
      if !ownedDraft.comment.isEmpty {
        try await ax.type("", resolving: composer)
        guard try draft() == PollDraft(comment: "", options: ownedDraft.options,
          hasAttachment: ownedDraft.hasAttachment) else { return false }
      }
      let remove = try ax.button("Remove app from message")
      try ax.press(remove)
      try await ax.wait("unsent poll to close") { try self.draft().isEmpty }
      self.ownedDraft = nil
      return true
    } catch { return false }
  }

  private func pollMenuItems() -> [AXUIElement] {
    // The app drawer may be a popover outside the main window.
    ax.descendants(ax.root, excluding: ["TranscriptCollectionView", "ConversationList"]).filter {
      [kAXButtonRole, kAXMenuItemRole].contains(ax.string($0, kAXRoleAttribute)) &&
        [ax.string($0, kAXDescriptionAttribute), ax.string($0, kAXTitleAttribute)].contains("Polls")
    }
  }
}
