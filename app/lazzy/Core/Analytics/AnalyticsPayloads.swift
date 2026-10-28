import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias AnalyticsMetadata = [String: AnalyticsValue]

public enum AnalyticsValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension AnalyticsValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AnalyticsValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AnalyticsValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AnalyticsValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AnalyticsValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

public struct NotificationOptions: Codable, Equatable, Sendable {
    public var title: String?
    public var body: String?
    public var description: String?
    public var sound: String?

    public init(
        title: String? = nil,
        body: String? = nil,
        description: String? = nil,
        sound: String? = nil
    ) {
        self.title = title
        self.body = body
        self.description = description
        self.sound = sound
    }
}

public struct AnalyticsEvent: Codable, Equatable, Sendable {
    public var eventName: String
    public var occurredAt: Date?
    public var userAnonID: String?
    public var sessionID: String?
    public var metadata: AnalyticsMetadata
    public var dedupeKey: String?
    public var notification: NotificationOptions?

    public init(
        eventName: String,
        occurredAt: Date? = Date(),
        userAnonID: String? = nil,
        sessionID: String? = nil,
        metadata: AnalyticsMetadata = [:],
        dedupeKey: String? = nil,
        notification: NotificationOptions? = nil
    ) {
        self.eventName = eventName
        self.occurredAt = occurredAt
        self.userAnonID = userAnonID
        self.sessionID = sessionID
        self.metadata = metadata
        self.dedupeKey = dedupeKey
        self.notification = notification
    }

    public init(
        type eventType: String,
        occurredAt: Date? = Date(),
        userAnonID: String? = nil,
        sessionID: String? = nil,
        metadata: AnalyticsMetadata = [:],
        dedupeKey: String? = nil,
        title: String? = nil,
        body: String? = nil,
        sound: String? = nil
    ) {
        self.init(
            eventName: eventType,
            occurredAt: occurredAt,
            userAnonID: userAnonID,
            sessionID: sessionID,
            metadata: metadata,
            dedupeKey: dedupeKey,
            notification: NotificationOptions(title: title, body: body, sound: sound)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case eventName = "event_name"
        case occurredAt = "occurred_at"
        case userAnonID = "user_anon_id"
        case sessionID = "session_id"
        case metadata = "properties"
        case dedupeKey = "dedupe_key"
        case notificationTitle = "notification_title"
        case notificationBody = "notification_body"
        case notificationDescription = "notification_description"
        case sound
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventName, forKey: .eventName)
        if let occurredAt {
            try container.encode(Self.iso8601Formatter.string(from: occurredAt), forKey: .occurredAt)
        }
        try container.encodeIfPresent(userAnonID, forKey: .userAnonID)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(dedupeKey, forKey: .dedupeKey)
        try container.encodeIfPresent(notification?.title, forKey: .notificationTitle)
        try container.encodeIfPresent(notification?.body, forKey: .notificationBody)
        try container.encodeIfPresent(notification?.description, forKey: .notificationDescription)
        try container.encodeIfPresent(notification?.sound, forKey: .sound)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventName = try container.decode(String.self, forKey: .eventName)
        if let occurredAtString = try container.decodeIfPresent(String.self, forKey: .occurredAt) {
            occurredAt = Self.iso8601Formatter.date(from: occurredAtString)
        } else {
            occurredAt = nil
        }
        userAnonID = try container.decodeIfPresent(String.self, forKey: .userAnonID)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        metadata = try container.decodeIfPresent(AnalyticsMetadata.self, forKey: .metadata) ?? [:]
        dedupeKey = try container.decodeIfPresent(String.self, forKey: .dedupeKey)

        let notification = NotificationOptions(
            title: try container.decodeIfPresent(String.self, forKey: .notificationTitle),
            body: try container.decodeIfPresent(String.self, forKey: .notificationBody),
            description: try container.decodeIfPresent(String.self, forKey: .notificationDescription),
            sound: try container.decodeIfPresent(String.self, forKey: .sound)
        )
        self.notification = notification.title == nil && notification.body == nil && notification.description == nil && notification.sound == nil
            ? nil
            : notification
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

public struct IngestResponse: Decodable, Equatable, Sendable {
    public let accepted: Int
    public let dropped: Int
    public let notificationsRequested: Int
    public let notificationsCreated: Int
    public let notificationsBlocked: Int
    public let overageNotifications: Int
    public let estimatedOverageCents: Int
    public let dispatchRequested: Bool
    public let dispatchRequestID: String?

    private enum CodingKeys: String, CodingKey {
        case accepted
        case dropped
        case notificationsRequested = "notifications_requested"
        case notificationsCreated = "notifications_created"
        case notificationsBlocked = "notifications_blocked"
        case overageNotifications = "overage_notifications"
        case estimatedOverageCents = "estimated_overage_cents"
        case dispatchRequested = "dispatch_requested"
        case dispatchRequestID = "dispatch_request_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decode(Int.self, forKey: .accepted)
        dropped = try container.decode(Int.self, forKey: .dropped)
        notificationsRequested = try container.decode(Int.self, forKey: .notificationsRequested)
        notificationsCreated = try container.decode(Int.self, forKey: .notificationsCreated)
        notificationsBlocked = try container.decode(Int.self, forKey: .notificationsBlocked)
        overageNotifications = try container.decode(Int.self, forKey: .overageNotifications)
        estimatedOverageCents = try container.decode(Int.self, forKey: .estimatedOverageCents)
        dispatchRequested = try container.decode(Bool.self, forKey: .dispatchRequested)
        if let stringID = try? container.decodeIfPresent(String.self, forKey: .dispatchRequestID) {
            dispatchRequestID = stringID
        } else if let intID = try? container.decodeIfPresent(Int.self, forKey: .dispatchRequestID) {
            dispatchRequestID = String(intID)
        } else {
            dispatchRequestID = nil
        }
    }
}

public enum AnalyticsLiteError: Error, Equatable, LocalizedError {
    case notConfigured
    case invalidConfiguration(String)
    case invalidEvent(String)
    case invalidBatchSize(Int)
    case httpStatus(Int, String?)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AnalyticsLite has not been configured."
        case .invalidConfiguration(let message):
            return message
        case .invalidEvent(let message):
            return message
        case .invalidBatchSize(let count):
            return "A single ingest request can contain at most \(Self.maxBatchSize) events. Received \(count)."
        case .httpStatus(let status, let message):
            return message ?? "Ingest request failed with HTTP \(status)."
        case .emptyResponse:
            return "The ingest endpoint returned an empty response."
        }
    }

    private static let maxBatchSize = 250
}

