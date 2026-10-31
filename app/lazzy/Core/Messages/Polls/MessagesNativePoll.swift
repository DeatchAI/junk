import Foundation

/// The pinned imsg 0.20 contract. Never infer a decision from its compatibility "vote" field.
struct MessagesNativePoll {
  struct Option: Equatable {
    let id: String
    let text: String
  }
  struct Vote {
    let optionID: String
    let participant: String
    let isSelected: Bool
  }
  let kind: String
  let guid: String?
  let originalGUID: String?
  let question: String?
  let options: [Option]
  let votes: [Vote]?

  init?(_ value: [String: Any]) {
    guard let kind = value["kind"] as? String else { return nil }
    self.kind = kind
    guid = Self.guid(value["poll_guid"] as? String)
    originalGUID = Self.guid(value["original_guid"] as? String)
    question = value["question"] as? String
    let rawOptions = value["options"] as? [[String: Any]] ?? []
    let parsed = rawOptions.compactMap { raw -> Option? in
      guard let id = raw["id"] as? String, !id.isEmpty,
        let text = raw["text"] as? String, !text.isEmpty else { return nil }
      return Option(id: id, text: text)
    }
    options = parsed.count == rawOptions.count ? parsed : []
    if let rawVotes = value["votes"] as? [[String: Any]] {
      let parsed = rawVotes.compactMap { raw -> Vote? in
        guard let id = raw["option_id"] as? String, !id.isEmpty,
          let participant = raw["participant"] as? String, !participant.isEmpty else { return nil }
        guard let state = (raw["event_type"] as? String)?.lowercased() else { return nil }
        let selected = ["selected", "select", "voted", "vote", "added", "add"]
        let removed = ["removed", "remove", "unselected", "deselected", "unvote", "unvoted"]
        guard selected.contains(state) || removed.contains(state) else { return nil }
        return Vote(optionID: id, participant: participant, isSelected: selected.contains(state))
      }
      votes = parsed.count == rawVotes.count ? parsed : nil
    } else {
      // Empty native snapshots omit both fields. A lone compatibility vote is ambiguous.
      votes = value["votes"] == nil && value["vote"] == nil ? [] : nil
    }
  }

  static func guid(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.count <= 250 else { return nil }
    let normalized = value.split(separator: "/").last.map(String.init) ?? value
    return normalized.uppercased()
  }
}

struct MessagesCreatedPoll {
  let guid: String
  let options: [MessagesNativePoll.Option]
}
