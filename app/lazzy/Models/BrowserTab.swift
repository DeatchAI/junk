import Foundation

struct BrowserTab: Codable, Identifiable, Equatable {
  let id: Int
  let windowId: Int?
  let active: Bool
  let title: String
  let url: String
  let faviconURL: String?
  let status: String
  let automatable: Bool
  let restrictionReason: String?

  enum CodingKeys: String, CodingKey {
    case id
    case windowId
    case active
    case title
    case url
    case faviconURL = "favIconUrl"
    case status
    case automatable
    case restrictionReason
  }

  init(
    id: Int,
    windowId: Int? = nil,
    active: Bool = false,
    title: String,
    url: String,
    faviconURL: String? = nil,
    status: String = "unknown",
    automatable: Bool = true,
    restrictionReason: String? = nil
  ) {
    self.id = id
    self.windowId = windowId
    self.active = active
    self.title = title
    self.url = url
    self.faviconURL = faviconURL
    self.status = status
    self.automatable = automatable
    self.restrictionReason = restrictionReason
  }

  var isWebTab: Bool {
    automatable && (url.hasPrefix("https://") || url.hasPrefix("http://"))
  }

  var attachment: BrowserTabAttachment {
    BrowserTabAttachment(
      id: id,
      windowId: windowId,
      active: active,
      title: title,
      url: url
    )
  }
}
