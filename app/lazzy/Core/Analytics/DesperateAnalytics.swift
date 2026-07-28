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

public final class AnalyticsLite {
    public static let defaultAppURL = URL(string: "https://nudges-liard.vercel.app")!
    public static let defaultIngestPath = "api/v1/events"

    public static var defaultIngestEndpoint: URL {
        ingestEndpoint(appURL: defaultAppURL)
    }

    public static func ingestEndpoint(appURL: URL) -> URL {
        let normalizedPath = appURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix(defaultIngestPath) {
            return appURL
        }

        return appURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("events")
    }

    public struct Configuration: Sendable {
        public var apiKey: String
        public var endpoint: URL
        public var maxBatchSize: Int
        public var defaultNotification: NotificationOptions?

        public init(
            apiKey: String,
            endpoint: URL = AnalyticsLite.defaultIngestEndpoint,
            maxBatchSize: Int = 50,
            defaultNotification: NotificationOptions? = nil
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.maxBatchSize = min(max(maxBatchSize, 1), AnalyticsLite.maxIngestBatchSize)
            self.defaultNotification = defaultNotification
        }

        public init(
            apiKey: String,
            appURL: URL,
            maxBatchSize: Int = 50,
            defaultNotification: NotificationOptions? = nil
        ) {
            self.init(
                apiKey: apiKey,
                endpoint: AnalyticsLite.ingestEndpoint(appURL: appURL),
                maxBatchSize: maxBatchSize,
                defaultNotification: defaultNotification
            )
        }

        public init(
            apiKey: String,
            endpoint: String,
            maxBatchSize: Int = 50,
            defaultNotification: NotificationOptions? = nil
        ) throws {
            guard let endpointURL = URL(string: endpoint) else {
                throw AnalyticsLiteError.invalidConfiguration("endpoint must be a valid URL")
            }
            self.init(
                apiKey: apiKey,
                endpoint: endpointURL,
                maxBatchSize: maxBatchSize,
                defaultNotification: defaultNotification
            )
        }

        public init(
            apiKey: String,
            appURL: String,
            maxBatchSize: Int = 50,
            defaultNotification: NotificationOptions? = nil
        ) throws {
            guard let appURL = URL(string: appURL) else {
                throw AnalyticsLiteError.invalidConfiguration("appURL must be a valid URL")
            }
            self.init(
                apiKey: apiKey,
                appURL: appURL,
                maxBatchSize: maxBatchSize,
                defaultNotification: defaultNotification
            )
        }
    }

    public static let shared = AnalyticsLite()

    private static let maxIngestBatchSize = 250
    private let lock = DispatchQueue(label: "com.desperate.analytics-lite")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var configuration: Configuration?
    private var urlSession: URLSession
    private var buffer: [AnalyticsEvent] = []

    public init(configuration: Configuration? = nil, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func configure(
        apiKey: String,
        endpoint: URL = AnalyticsLite.defaultIngestEndpoint,
        maxBatchSize: Int = 50,
        defaultNotification: NotificationOptions? = nil,
        urlSession: URLSession = .shared
    ) {
        let configuration = Configuration(
            apiKey: apiKey,
            endpoint: endpoint,
            maxBatchSize: maxBatchSize,
            defaultNotification: defaultNotification
        )
        lock.sync {
            self.configuration = configuration
            self.urlSession = urlSession
        }
    }

    public func configure(
        apiKey: String,
        appURL: URL,
        maxBatchSize: Int = 50,
        defaultNotification: NotificationOptions? = nil,
        urlSession: URLSession = .shared
    ) {
        configure(
            apiKey: apiKey,
            endpoint: AnalyticsLite.ingestEndpoint(appURL: appURL),
            maxBatchSize: maxBatchSize,
            defaultNotification: defaultNotification,
            urlSession: urlSession
        )
    }

    public func configure(
        apiKey: String,
        endpoint: String,
        maxBatchSize: Int = 50,
        defaultNotification: NotificationOptions? = nil,
        urlSession: URLSession = .shared
    ) throws {
        guard let endpointURL = URL(string: endpoint) else {
            throw AnalyticsLiteError.invalidConfiguration("endpoint must be a valid URL")
        }
        configure(
            apiKey: apiKey,
            endpoint: endpointURL,
            maxBatchSize: maxBatchSize,
            defaultNotification: defaultNotification,
            urlSession: urlSession
        )
    }

    public func configure(
        apiKey: String,
        appURL: String,
        maxBatchSize: Int = 50,
        defaultNotification: NotificationOptions? = nil,
        urlSession: URLSession = .shared
    ) throws {
        guard let appURL = URL(string: appURL) else {
            throw AnalyticsLiteError.invalidConfiguration("appURL must be a valid URL")
        }
        configure(
            apiKey: apiKey,
            appURL: appURL,
            maxBatchSize: maxBatchSize,
            defaultNotification: defaultNotification,
            urlSession: urlSession
        )
    }

    public func track(
        _ eventType: String,
        userAnonID: String? = nil,
        sessionID: String? = nil,
        metadata: AnalyticsMetadata = [:],
        dedupeKey: String? = nil,
        title: String? = nil,
        body: String? = nil,
        sound: String? = nil
    ) async throws -> [IngestResponse] {
        let event = AnalyticsEvent(
            type: eventType,
            userAnonID: userAnonID,
            sessionID: sessionID,
            metadata: metadata,
            dedupeKey: dedupeKey,
            title: title,
            body: body,
            sound: sound
        )
        return try await track(event)
    }

    public func track(_ event: AnalyticsEvent) async throws -> [IngestResponse] {
        let currentConfiguration = try resolvedConfiguration()
        let eventWithDefaults = applyingDefaults(to: event, defaultNotification: currentConfiguration.defaultNotification)
        try validate(eventWithDefaults)

        let shouldFlush = lock.sync { () -> Bool in
            buffer.append(eventWithDefaults)
            return buffer.count >= currentConfiguration.maxBatchSize
        }

        return shouldFlush ? try await flush() : []
    }

    public func enqueue(
        _ eventType: String,
        userAnonID: String? = nil,
        sessionID: String? = nil,
        metadata: AnalyticsMetadata = [:],
        dedupeKey: String? = nil,
        title: String? = nil,
        body: String? = nil,
        sound: String? = nil
    ) throws {
        let event = AnalyticsEvent(
            type: eventType,
            userAnonID: userAnonID,
            sessionID: sessionID,
            metadata: metadata,
            dedupeKey: dedupeKey,
            title: title,
            body: body,
            sound: sound
        )
        let currentConfiguration = try resolvedConfiguration()
        let eventWithDefaults = applyingDefaults(to: event, defaultNotification: currentConfiguration.defaultNotification)
        try validate(eventWithDefaults)
        lock.sync {
            buffer.append(eventWithDefaults)
        }
    }

    public func flush() async throws -> [IngestResponse] {
        let events = lock.sync { () -> [AnalyticsEvent] in
            let events = buffer
            buffer.removeAll(keepingCapacity: true)
            return events
        }

        do {
            return try await send(events: events)
        } catch {
            lock.sync {
                buffer = events + buffer
            }
            throw error
        }
    }

    @discardableResult
    public func send(_ event: AnalyticsEvent) async throws -> IngestResponse {
        guard let response = try await send(events: [event]).first else {
            throw AnalyticsLiteError.emptyResponse
        }
        return response
    }

    @discardableResult
    public func send(events: [AnalyticsEvent]) async throws -> [IngestResponse] {
        guard !events.isEmpty else { return [] }
        let currentConfiguration = try resolvedConfiguration()
        let normalizedEvents = try events.map { event in
            let eventWithDefaults = applyingDefaults(to: event, defaultNotification: currentConfiguration.defaultNotification)
            try validate(eventWithDefaults)
            return eventWithDefaults
        }

        var responses: [IngestResponse] = []
        for batch in normalizedEvents.chunked(into: currentConfiguration.maxBatchSize) {
            responses.append(try await sendBatch(batch, configuration: currentConfiguration))
        }
        return responses
    }

    private func sendBatch(_ events: [AnalyticsEvent], configuration: Configuration) async throws -> IngestResponse {
        guard events.count <= Self.maxIngestBatchSize else {
            throw AnalyticsLiteError.invalidBatchSize(events.count)
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(IngestRequest(events: events))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsLiteError.httpStatus(-1, "The ingest endpoint returned a non-HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AnalyticsLiteError.httpStatus(httpResponse.statusCode, Self.apiErrorMessage(from: data))
        }

        guard !data.isEmpty else {
            throw AnalyticsLiteError.emptyResponse
        }

        return try decoder.decode(IngestResponse.self, from: data)
    }

    private func resolvedConfiguration() throws -> Configuration {
        let configuration = lock.sync { self.configuration }
        guard let configuration else {
            throw AnalyticsLiteError.notConfigured
        }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalyticsLiteError.invalidConfiguration("apiKey is required")
        }
        return configuration
    }

    private func validate(_ event: AnalyticsEvent) throws {
        let eventName = event.eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventName.isEmpty else {
            throw AnalyticsLiteError.invalidEvent("eventName is required")
        }
        guard eventName.count <= 120 else {
            throw AnalyticsLiteError.invalidEvent("eventName must be 120 characters or fewer")
        }
        try validateOptional(event.userAnonID, label: "userAnonID", maxLength: 256)
        try validateOptional(event.sessionID, label: "sessionID", maxLength: 256)
        try validateOptional(event.dedupeKey, label: "dedupeKey", maxLength: 256)
        try validateOptional(event.notification?.title, label: "notification title", maxLength: 120)
        try validateOptional(event.notification?.body, label: "notification body", maxLength: 280)
        try validateOptional(event.notification?.description, label: "notification description", maxLength: 280)
        try validateOptional(event.notification?.sound, label: "notification sound", maxLength: 80)
    }

    private func validateOptional(_ value: String?, label: String, maxLength: Int) throws {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnalyticsLiteError.invalidEvent("\(label) cannot be empty")
        }
        guard trimmed.count <= maxLength else {
            throw AnalyticsLiteError.invalidEvent("\(label) must be \(maxLength) characters or fewer")
        }
    }

    private func applyingDefaults(
        to event: AnalyticsEvent,
        defaultNotification: NotificationOptions?
    ) -> AnalyticsEvent {
        guard let defaultNotification else { return event }

        var event = event
        let existing = event.notification
        event.notification = NotificationOptions(
            title: existing?.title ?? defaultNotification.title,
            body: existing?.body ?? defaultNotification.body,
            description: existing?.description ?? defaultNotification.description,
            sound: existing?.sound ?? defaultNotification.sound
        )
        return event
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if
            let error = try? JSONDecoder().decode(APIError.self, from: data),
            !error.error.isEmpty
        {
            return error.error
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct IngestRequest: Encodable {
    let events: [AnalyticsEvent]
}

private struct APIError: Decodable {
    let error: String
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
