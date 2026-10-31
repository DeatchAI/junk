import ApplicationServices
import Combine
import Foundation

@MainActor
final class MessagesRemoteController: ObservableObject {
  static let shared = MessagesRemoteController()
  enum State: Equatable {
    case off, needsSetup, pairing, connecting, ready, needsPermission, error(String)
    var label: String {
      switch self {
      case .off: "Off"
      case .needsSetup: "Setup needed"
      case .pairing: "Waiting for your iPhone"
      case .connecting: "Connecting"
      case .ready: "Connected"
      case .needsPermission: "Messages access needed"
      case .error(let message): message
      }
    }
  }

  @Published private(set) var state: State = .off
  @Published private(set) var pairing: MessagesPairingSession?
  @Published private(set) var pairingHint: String?
  @Published private(set) var pairedSender: String?
  @Published private(set) var isEnabled: Bool
  @Published private(set) var hasMessagesAccess = false
  @Published private(set) var isCheckingMessagesAccess = false
  @Published private(set) var isDiscoveringAddress = false
  @Published private(set) var agentAddress: String

  @Published private(set) var pollsEnabled: Bool
  @Published private(set) var hasPollAccess: Bool
  @Published private(set) var pollStatus: String?
  @Published private(set) var isSendingPoll = false
  @Published private(set) var isSendingTestPoll = false
  @Published private(set) var pollsPaused = false
  private var pollTask: Task<Void, Never>?
  private let pollSender: MessagesPollSending
  private let voteDelayNanoseconds: UInt64
  private lazy var polls = MessagesPollCoordinator(sender: pollSender,
    isPending: { [weak self] decision in
      guard let self, self.isEnabled, self.pollsEnabled, self.state == .ready else { return false }
      if case .test = decision.target { return true }
      return self.commands?.isPending(decision) == true
    }, apply: { [weak self] decision, index in
      guard let self else { return false }
      if case .native(let code, _) = decision.target { return self.commands?.choose(code, number: index + 1) == true }
      self.pollStatus = "Received “\(decision.options[index])” from your iPhone."
      return true
    }, notice: { [weak self] in self?.send($0) }, settleNanoseconds: voteDelayNanoseconds)

  private let rpc: MessagesRPCTransport
  private let settings: MessagesRemoteSettings
  private var subscriptionID: Int?
  private var subscribing = false
  private var epoch = UUID()
  private var pairingExpiry: DispatchWorkItem?
  private var seenMessageIDs = Set<Int>()
  private var relay: MessagesActivityRelay?
  private var commands: MessagesActivityCommands?
  private var sending = false
  private struct Delivery {
    let chatID: Int
    enum Content { case text(String), poll(MessagesPollDecision) }
    let content: Content
    let completion: ((Result<Void, Error>) -> Void)?
  }
  private var outbox: [Delivery] = []

  var isPaired: Bool { settings.chatID != nil && pairedSender != nil }

  init(rpc: MessagesRPCTransport? = nil, settings: MessagesRemoteSettings? = nil, pollSender: MessagesPollSending? = nil, voteDelayNanoseconds: UInt64 = 900_000_000) {
    let rpc = rpc ?? ImsgRPCClient()
    let settings = settings ?? MessagesRemoteSettings()
    self.rpc = rpc
    let nativeSender = pollSender ?? MessagesNativePollSender(rpc: rpc)
    self.pollSender = nativeSender
    self.voteDelayNanoseconds = voteDelayNanoseconds
    pollsEnabled = settings.pollsEnabled
    hasPollAccess = nativeSender.hasAccess
    self.settings = settings
    agentAddress = settings.agentAddress
    pairedSender = settings.sender
    isEnabled = settings.enabled
    rpc.onMessage = { [weak self] in self?.receive($0) }
    rpc.onStreamError = { [weak self] in self?.connectionFailed($0) }
    rpc.onError = { [weak self] in self?.connectionFailed($0) }
  }

  func configure(store: DetachedRunStore, controls: DetachedRunControls,
    approvalResponse: ((String, Bool) -> Bool)? = nil) {
    let commands = MessagesActivityCommands(store: store, controls: controls) { [weak self] in self?.send($0) }
    commands.approvalResponse = approvalResponse
    self.commands = commands
    let relay = MessagesActivityRelay(store: store) { [weak self] in self?.send($0) }
    relay.questionText = { [weak commands] in commands?.questionText(for: $0) }
    relay.questionIdentity = { [weak commands] in commands?.questionIdentity(for: $0) }
    relay.decision = { [weak self] in self?.forwardDecision($0) ?? false }
    relay.approvalText = { [weak commands] in commands?.approvalText(for: $0) }
    self.relay = relay
    relay.setEnabled(isEnabled && state == .ready)
  }

  func recordResult(runID: String?, text: String) {
    if let runID { relay?.recordResult(runID: runID, text: text) }
  }

  func checkMessagesAccess(offerPairing: Bool = false) {
    guard !isCheckingMessagesAccess else { return }
    isCheckingMessagesAccess = true
    let generation = epoch
    startBridge { [weak self] in
      self?.rpc.request("status", params: [:]) { [weak self] result in
        guard let self, self.epoch == generation else { return }
        self.isCheckingMessagesAccess = false
        switch result {
        case .success(let status):
          self.hasMessagesAccess = (status["database"] as? [String: Any])?["ready"] as? Bool == true
          if !self.hasMessagesAccess {
            self.clearWatch()
            self.relay?.setEnabled(false)
            self.pairing = nil
            self.state = .needsPermission
          } else {
            if self.state == .needsPermission { self.state = .needsSetup }
            if offerPairing { self.preparePairing() }
          }
        case .failure(let error): self.connectionFailed(error.localizedDescription)
        }
      }
    }
  }

  /// Recent chats expose the local receiving address without loading their message history.
  private func preparePairing() {
    guard !isPaired, pairing == nil, state != .connecting, !isDiscoveringAddress else { return }
    if !agentAddress.isEmpty { beginPairing(agentAddress: agentAddress); return }
    isDiscoveringAddress = true
    let generation = epoch
    rpc.request("chats.list", params: ["limit": 20]) { [weak self] result in
      guard let self, self.epoch == generation else { return }
      self.isDiscoveringAddress = false
      guard case .success(let response) = result,
        let address = MessagesAccountDiscovery.address(in: response) else {
        self.state = .needsSetup
        return
      }
      self.beginPairing(agentAddress: address)
    }
  }

  func beginPairing(agentAddress: String) {
    guard !isPaired else { return }
    guard let session = MessagesPairingSession(agentAddress: agentAddress) else {
      state = .error("Enter the iMessage email or phone number signed into Messages on this Mac.")
      return
    }
    stop()
    settings.agentAddress = session.agentAddress
    self.agentAddress = session.agentAddress
    state = .connecting
    pairingHint = "Preparing a secure pairing code…"
    startBridge { [weak self] in
      self?.replaceWatch(params: [:]) { [weak self] in
        guard let self else { return }
        // Publish the QR only after the watcher is actually listening.
        self.pairing = session
        self.state = .pairing
        self.pairingHint = "Scan with your iPhone Camera, open Messages, then tap Send."
        let expiry = DispatchWorkItem { [weak self] in
          guard let self, self.pairing?.token == session.token else { return }
          self.pairing = nil
          self.clearWatch()
          self.state = .needsSetup
          self.pairingHint = "This QR expired. Create a new one to pair."
        }
        self.pairingExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, session.expiresAt.timeIntervalSinceNow), execute: expiry)
      }
    }
  }

  func resumeIfPaired() {
    guard isEnabled, subscriptionID == nil, !subscribing, let chatID = settings.chatID else { return }
    state = .connecting
    startBridge { [weak self] in
      self?.replaceWatch(params: ["chat_id": chatID]) { [weak self] in
        self?.state = .ready
        self?.relay?.setEnabled(true)
      }
    }
  }

  func enablePairedConnection() {
    guard isPaired else { return }
    stop()
    settings.enabled = true
    isEnabled = true
    resumeIfPaired()
  }

  func disable() {
    settings.enabled = false
    isEnabled = false
    stop()
  }

  func stop(clearPairing: Bool = false) {
    epoch = UUID()
    pairingExpiry?.cancel()
    pairingExpiry = nil
    pairing = nil
    pairingHint = nil
    subscriptionID = nil
    subscribing = false
    sending = false
    isCheckingMessagesAccess = false
    isDiscoveringAddress = false
    commands?.resetChoices()
    pollTask?.cancel(); pollTask = nil
    polls.reset()
    isSendingPoll = false
    isSendingTestPoll = false
    outbox.removeAll()
    seenMessageIDs.removeAll()
    relay?.setEnabled(false)
    rpc.stop()
    if clearPairing {
      settings.clearPairing()
      pairedSender = nil
      isEnabled = false
    }
    state = .off
  }

  private func startBridge(ready: @escaping () -> Void) {
    guard LicenseManager.shared.requireAccess() else { stop(); return }
    let generation = epoch
    do {
      try rpc.start { [weak self] result in
        guard let self, self.epoch == generation else { return }
        switch result {
        case .success: ready()
        case .failure(let error): self.connectionFailed(error.localizedDescription)
        }
      }
    } catch { connectionFailed(error.localizedDescription) }
  }

  private func replaceWatch(params: [String: Any], ready: @escaping () -> Void) {
    let generation = epoch
    let subscribe = { [weak self] in
      guard let self, self.epoch == generation else { return }
      self.subscribing = true
      self.rpc.request("watch.subscribe", params: params) { [weak self] result in
        guard let self, self.epoch == generation else { return }
        self.subscribing = false
        switch result {
        case .success(let response):
          guard let id = response["subscription"] as? Int, id > 0 else {
            self.connectionFailed("Messages did not confirm its live connection.")
            return
          }
          self.subscriptionID = id
          self.hasMessagesAccess = true
          ready()
        case .failure(let error): self.connectionFailed(error.localizedDescription)
        }
      }
    }
    if let id = subscriptionID {
      subscriptionID = nil
      rpc.request("watch.unsubscribe", params: ["subscription": id]) { [weak self] result in
        guard let self, self.epoch == generation else { return }
        if case .failure(let error) = result { self.connectionFailed(error.localizedDescription) }
        else { subscribe() }
      }
    } else { subscribe() }
  }

  private func clearWatch() {
    if let id = subscriptionID { rpc.request("watch.unsubscribe", params: ["subscription": id]) { _ in } }
    subscriptionID = nil
  }

  private func receive(_ envelope: [String: Any]) {
    guard let params = envelope["params"] as? [String: Any],
      params["subscription"] as? Int == subscriptionID,
      let message = MessagesIncomingMessage(envelope) else { return }
    guard seenMessageIDs.insert(message.id).inserted else { return }
    if seenMessageIDs.count > 1_000 { seenMessageIDs = [message.id] }
    if !isPaired, state == .pairing, let session = pairing {
      guard session.accepts(message.text) else {
        if !message.isFromMe, message.text.lowercased().hasPrefix("pair ") {
          pairingHint = "That code is not current. Scan the QR shown here and send the new code."
        }
        return
      }
      guard !message.isFromMe else {
        pairingHint = "This arrived as a sent message. Send from your iPhone’s personal account to the agent account on this Mac."
        return
      }
      guard !message.isGroup else {
        pairingHint = "Messages marks this as a group conversation. Send the code in a new one-to-one conversation."
        return
      }
      inspectPairingConversation(message, session: session)
      return
    }
    guard isEnabled, state == .ready, !message.isFromMe, !message.isGroup,
      message.chatID == settings.chatID, let pairedSender,
      MessagesIncomingMessage.sameSender(message.sender, pairedSender) else { return }
    if message.isPollEvent {
      if pollsEnabled { polls.receive(message) }
    } else { commands?.handle(message.text) }
  }

  private func inspectPairingConversation(_ message: MessagesIncomingMessage, session: MessagesPairingSession) {
    let generation = epoch
    state = .connecting
    pairingHint = "Your code arrived. Checking the Messages conversation…"
    rpc.request("chats.get", params: ["chat_id": message.chatID]) { [weak self] result in
      guard let self, self.epoch == generation, self.pairing?.token == session.token else { return }
      switch result {
      case .success(let response):
        guard let chat = MessagesChatIdentity(response) else {
          self.state = .pairing
          self.pairingHint = "Your code arrived, but Messages did not return complete conversation details. Reopen Detach and try again."
          return
        }
        if let reason = chat.rejectionReason(chatID: message.chatID, sender: message.sender) {
          self.state = .pairing
          self.pairingHint = reason
          return
        }
        self.confirmPairing(message)
      case .failure:
        self.state = .pairing
        self.pairingHint = "Your code arrived, but Detach couldn’t read the conversation details. Check Messages access and send the code again."
      }
    }
  }

  private func confirmPairing(_ message: MessagesIncomingMessage) {
    pairingExpiry?.cancel()
    pairing = nil
    state = .connecting
    pairingHint = "Pairing message received. Allow Detach to control Messages if macOS asks."
    replaceWatch(params: ["chat_id": message.chatID]) { [weak self] in
      self?.enqueue("Connected to Detach. You’ll hear when a task finishes or needs your input. All projects are included. Send status for current work or help for commands.",
        chatID: message.chatID) { [weak self] result in
        guard let self else { return }
        switch result {
        case .success:
          self.settings.pair(chatID: message.chatID, sender: message.sender)
          self.pairedSender = message.sender
          self.isEnabled = true
          self.pairingHint = nil
          self.state = .ready
          self.relay?.setEnabled(true)
        case .failure:
          self.pairingHint = "Your message arrived, but the reply was not confirmed. Check Automation access, then create a new QR. Detach will not resend it automatically."
        }
      }
    }
  }

  private func send(_ text: String) {
    guard isEnabled, state == .ready, let chatID = settings.chatID else { return }
    enqueue(text, chatID: chatID)
  }

  private func enqueue(_ text: String, chatID: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
    guard !text.isEmpty else { completion?(.success(())); return }
    var rest = text[...]
    while !rest.isEmpty {
      let end = rest.index(rest.startIndex, offsetBy: 2_800, limitedBy: rest.endIndex) ?? rest.endIndex
      let part = String(rest[..<end])
      rest = rest[end...]
      outbox.append(Delivery(chatID: chatID, content: .text(part), completion: rest.isEmpty ? completion : nil))
    }
    deliverNext()
  }

  private func deliverNext() {
    guard !sending, !outbox.isEmpty else { return }
    sending = true
    let item = outbox.removeFirst(), generation = epoch
    if case .poll(let decision) = item.content {
      guard pollsEnabled, !pollsPaused, let recipient = pairedSender, polls.pending(decision) else {
        if case .test = decision.target { isSendingTestPoll = false }
        sending = false
        deliverNext()
        return
      }
      isSendingPoll = true
      pollTask = Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          try await self.polls.send(decision, chatID: item.chatID, recipient: recipient)
          if self.epoch == generation {
            self.pollStatus = nil
            if case .test = decision.target {
              self.isSendingTestPoll = false
              self.pollStatus = "Poll sent. Choose one option on your iPhone."
            }
          }
        } catch {
          guard self.epoch == generation else { return }
          if case .test = decision.target { self.isSendingTestPoll = false }
          if !(error is CancellationError) {
            self.pollsPaused = (error as? MessagesPollSendFailure)?.requiresPause ?? true
            self.pollStatus = error.localizedDescription
            let context = decision.caption.components(separatedBy: " · ").prefix(3).joined(separator: " · ")
            self.send("\(context)\nPoll unavailable. Review this decision in Detach on your Mac.")
          }
        }
        guard self.epoch == generation else { return }
        self.isSendingPoll = false
        self.sending = false
        self.pollTask = nil
        self.deliverNext()
      }
      return
    }
    guard case .text(let text) = item.content else { return }
    rpc.request("send", params: ["chat_id": item.chatID, "text": text, "transport": "applescript"]) { [weak self] result in
      guard let self, self.epoch == generation else { return }
      self.sending = false
      switch result {
      case .success(let response) where response["ok"] as? Bool == true:
        item.completion?(.success(()))
        self.deliverNext()
      default:
        let error: Error
        if case .failure(let failure) = result { error = failure }
        else { error = ImsgRPCClient.RPCError.invalidResponse }
        self.outbox.removeAll()
        self.connectionFailed("Message delivery was not confirmed. Check Messages Automation access, then reconnect.")
        item.completion?(.failure(error))
      }
    }
  }

  private func connectionFailed(_ message: String) {
    subscribing = false
    subscriptionID = nil
    isCheckingMessagesAccess = false
    pairingExpiry?.cancel()
    pairing = nil
    relay?.setEnabled(false)
    commands?.resetChoices()
    pollTask?.cancel(); pollTask = nil
    polls.reset()
    isSendingPoll = false
    isSendingTestPoll = false
    outbox.removeAll()
    isDiscoveringAddress = false
    state = .error(message)
  }
  func refreshPollAccess() { hasPollAccess = pollSender.hasAccess }

  func setPollsEnabled(_ enabled: Bool) {
    settings.pollsEnabled = enabled
    pollsEnabled = enabled
    pollsPaused = false
    pollStatus = nil
    pollTask?.cancel()
    polls.reset()
    commands?.resetChoices()
    if enabled && !pollSender.hasAccess { NativePermissionRequests.requestAccessibility() }
    refreshPollAccess()
    relay?.setEnabled(false)
    relay?.setEnabled(isEnabled && state == .ready)
  }

  func resumePolls() {
    pollsPaused = false
    pollStatus = nil
    refreshPollAccess()
    relay?.setEnabled(false)
    relay?.setEnabled(isEnabled && state == .ready)
  }

  func sendTestPoll() {
    guard pollsEnabled, hasPollAccess, isEnabled, state == .ready, !isSendingPoll, !isSendingTestPoll,
      let chatID = settings.chatID,
      let decision = MessagesPollDecision.make(target: .test, heading: "Detach",
        question: "Can you receive and answer polls?", options: ["Looks good", "Try again"], lifetime: 300) else { return }
    pollsPaused = false
    isSendingTestPoll = true
    pollStatus = "Preparing a test poll…"
    outbox.append(Delivery(chatID: chatID, content: .poll(decision), completion: nil))
    deliverNext()
  }

  #if DEBUG
  func sendConsecutiveTestPolls() {
    guard pollsEnabled, hasPollAccess, isEnabled, state == .ready, !isSendingPoll, !isSendingTestPoll,
      let chatID = settings.chatID else { return }
    let samples: [(String, [String])] = [
      ("Test 1 of 2: choose a report style. This only tests Messages.", ["Minimal", "Detailed", "Both"]),
      ("Test 2 of 2: approve a fictional report? No agent action will run.", ["Approve once", "Deny"])
    ]
    let decisions = samples.compactMap {
      MessagesPollDecision.make(target: .test, heading: "Detach delivery test",
        question: $0.0, options: $0.1, lifetime: 300)
    }
    guard decisions.count == 2 else { return }
    pollsPaused = false
    isSendingTestPoll = true
    pollStatus = "Sending two test polls…"
    outbox.append(contentsOf: decisions.map { Delivery(chatID: chatID, content: .poll($0), completion: nil) })
    deliverNext()
  }
  #endif

  private func forwardDecision(_ run: DetachedAgentRun) -> Bool {
    guard pollsEnabled, isEnabled, state == .ready, let chatID = settings.chatID else { return false }
    guard hasPollAccess, !pollsPaused else {
      let reason = hasPollAccess ? "Resume interactive polls in Messages Remote settings."
        : "Allow Detach in Accessibility to use polls."
      send("\(MessagesActivityRelay.heading(run))\n\(run.stateLabel). Open Detach on your Mac. \(reason)")
      return true
    }
    let decisions = commands?.polls(for: run) ?? []
    guard !decisions.isEmpty else { return false }
    for decision in decisions {
      outbox.append(Delivery(chatID: chatID, content: .poll(decision), completion: nil))
    }
    let questionIDs = Set(decisions.compactMap { decision -> String? in
      if case .native(_, .question(_, _, let id)) = decision.target { return id }
      return nil
    })
    if !questionIDs.isEmpty, let rest = commands?.questionText(for: run, excluding: questionIDs), !rest.isEmpty {
      enqueue("\(MessagesActivityRelay.heading(run))\n\(rest)", chatID: chatID)
    }
    deliverNext()
    return true
  }

}
