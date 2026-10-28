import Foundation

/// Retains heterogeneous tool details without requiring provider-specific native models.
indirect enum ActivityJSONValue: Codable, Equatable {
  case string(String), number(Double), bool(Bool), object([String: ActivityJSONValue]), array([ActivityJSONValue]), null

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() { self = .null }
    else if let item = try? value.decode(String.self) { self = .string(item) }
    else if let item = try? value.decode(Bool.self) { self = .bool(item) }
    else if let item = try? value.decode(Double.self) { self = .number(item) }
    else if let item = try? value.decode([String: ActivityJSONValue].self) { self = .object(item) }
    else { self = .array(try value.decode([ActivityJSONValue].self)) }
  }

  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .string(let item): try value.encode(item)
    case .number(let item): try value.encode(item)
    case .bool(let item): try value.encode(item)
    case .object(let item): try value.encode(item)
    case .array(let item): try value.encode(item)
    case .null: try value.encodeNil()
    }
  }

  var displayText: String {
    if case .string(let value) = self { return value }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
  }
}
