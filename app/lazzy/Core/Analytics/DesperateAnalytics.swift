import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
