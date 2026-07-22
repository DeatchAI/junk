import Foundation

/// Represents a quick action button in the floating menu
struct QuickAction: Identifiable, Equatable, Codable {
  let id: String
  let title: String
  let shortcut: String?  // e.g. "⌘L"
  let systemImage: String?  // SF Symbol name
  let prompt: String?  // AI prompt for custom actions
  let integrations: [String]?  // Legacy v1 integration names
  let mcpServerIds: [String]?  // Explicit v2 MCP capabilities
  let skills: [SkillAttachment]?  // Explicit v2 skill capabilities
  let learnedSkillPath: String?
  let learnedSkillVersion: Int?
  let learningStatus: String?
  let lastSuccessfulRunAt: Int?
  let kind: String
  let trigger: String
  let inputPolicy: String
  let executionMode: String
  let enabled: Bool
  let position: Int
  let isCustom: Bool  // Distinguishes from built-in actions

  // For decoding from server (uses 'name' instead of 'title')
  enum CodingKeys: String, CodingKey {
    case id
    case name
    case title
    case shortcut
    case systemImage
    case prompt
    case integrations
    case mcpServerIds
    case skills
    case learnedSkillPath
    case learnedSkillVersion
    case learningStatus
    case lastSuccessfulRunAt
    case kind
    case trigger
    case inputPolicy
    case executionMode
    case isCustom
    case enabled
    case position
  }

  init(
    id: String, title: String, shortcut: String? = nil, systemImage: String? = nil,
    prompt: String? = nil, integrations: [String]? = nil, mcpServerIds: [String]? = nil,
    skills: [SkillAttachment]? = nil, learnedSkillPath: String? = nil,
    learnedSkillVersion: Int? = nil, learningStatus: String? = nil,
    lastSuccessfulRunAt: Int? = nil, kind: String = "quick_action",
    trigger: String = "selection_menu", inputPolicy: String = "optional_selection",
    executionMode: String = "run_immediately", enabled: Bool = true, position: Int = 0,
    isCustom: Bool = false
  ) {
    self.id = id
    self.title = title
    self.shortcut = shortcut
    self.systemImage = systemImage
    self.prompt = prompt
    self.integrations = integrations
    self.mcpServerIds = mcpServerIds
    self.skills = skills
    self.learnedSkillPath = learnedSkillPath
    self.learnedSkillVersion = learnedSkillVersion
    self.learningStatus = learningStatus
    self.lastSuccessfulRunAt = lastSuccessfulRunAt
    self.kind = kind
    self.trigger = trigger
    self.inputPolicy = inputPolicy
    self.executionMode = executionMode
    self.enabled = enabled
    self.position = position
    self.isCustom = isCustom
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    // Server uses 'name', client uses 'title'
    if let name = try container.decodeIfPresent(String.self, forKey: .name) {
      title = name
    } else {
      title = try container.decode(String.self, forKey: .title)
    }
    shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
    systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage)
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
    integrations = try container.decodeIfPresent([String].self, forKey: .integrations)
    mcpServerIds = try container.decodeIfPresent([String].self, forKey: .mcpServerIds)
    skills = try container.decodeIfPresent([SkillAttachment].self, forKey: .skills)
    learnedSkillPath = try container.decodeIfPresent(String.self, forKey: .learnedSkillPath)
    learnedSkillVersion = try container.decodeIfPresent(Int.self, forKey: .learnedSkillVersion)
    learningStatus = try container.decodeIfPresent(String.self, forKey: .learningStatus)
    lastSuccessfulRunAt = try container.decodeIfPresent(Int.self, forKey: .lastSuccessfulRunAt)
    kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "quick_action"
    trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? "selection_menu"
    inputPolicy =
      try container.decodeIfPresent(String.self, forKey: .inputPolicy) ?? "optional_selection"
    executionMode =
      try container.decodeIfPresent(String.self, forKey: .executionMode) ?? "run_immediately"
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
    isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? true
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .name)
    try container.encodeIfPresent(shortcut, forKey: .shortcut)
    try container.encodeIfPresent(systemImage, forKey: .systemImage)
    try container.encodeIfPresent(prompt, forKey: .prompt)
    try container.encodeIfPresent(integrations, forKey: .integrations)
    try container.encodeIfPresent(mcpServerIds, forKey: .mcpServerIds)
    try container.encodeIfPresent(skills, forKey: .skills)
    try container.encodeIfPresent(learnedSkillPath, forKey: .learnedSkillPath)
    try container.encodeIfPresent(learnedSkillVersion, forKey: .learnedSkillVersion)
    try container.encodeIfPresent(learningStatus, forKey: .learningStatus)
    try container.encodeIfPresent(lastSuccessfulRunAt, forKey: .lastSuccessfulRunAt)
    try container.encode(kind, forKey: .kind)
    try container.encode(trigger, forKey: .trigger)
    try container.encode(inputPolicy, forKey: .inputPolicy)
    try container.encode(executionMode, forKey: .executionMode)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(position, forKey: .position)
    try container.encode(isCustom, forKey: .isCustom)
  }

  static let defaultActions: [QuickAction] = [
    QuickAction(
      id: "chat", title: "Chat", shortcut: "⌘L", systemImage: "bubble.left", prompt: nil,
      integrations: nil, isCustom: false),
    QuickAction(
      id: "screenshot", title: "Snip", shortcut: nil, systemImage: "camera.viewfinder", prompt: nil,
      integrations: nil, isCustom: false),
    QuickAction(
      id: "more", title: "…", shortcut: nil, systemImage: nil, prompt: nil, integrations: nil,
      isCustom: false),
  ]
}
