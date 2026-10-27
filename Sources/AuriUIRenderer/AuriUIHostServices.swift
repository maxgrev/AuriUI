#if os(iOS) || os(macOS)
import AuriUI
import Foundation

/// The work a host must perform to compose a generated screen.
@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIStreamRequest: Equatable, Sendable {
    public let brief: String
    public let grounded: Bool

    public init(brief: String, grounded: Bool = true) {
        self.brief = brief
        self.grounded = grounded
    }
}

/// A stream must deliver a complete `document` before its result can be saved.
/// Deltas remain interactive while composing. Ending after deltas alone marks
/// the visible partial screen as failed and disables its interactions.
@available(iOS 17.0, macOS 14.0, *)
public enum AuriUIStreamEvent: Equatable, Sendable {
    case designing
    case resources([String: URL])
    case delta(String)
    case document(text: String, screenID: String?)
}

@available(iOS 17.0, macOS 14.0, *)
public enum AuriUICapabilityExposure: Equatable, Sendable {
    case composer
    case hostOnly
}

/// Describes an action the containing app supports. Host-only capabilities
/// can be used by programmatic documents but cannot be parsed from model text.
@available(iOS 17.0, macOS 14.0, *)
public struct AuriUICapability: Identifiable, Sendable {
    public let id: String
    public let description: String
    public var acceptsFormInput: Bool
    public var exposure: AuriUICapabilityExposure
    public var isAvailable: @MainActor @Sendable () -> Bool

    public init(
        id: String,
        description: String,
        acceptsFormInput: Bool = false,
        exposure: AuriUICapabilityExposure = .composer,
        isAvailable: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.id = id
        self.description = description
        self.acceptsFormInput = acceptsFormInput
        self.exposure = exposure
        self.isAvailable = isAvailable
    }

    public static let navigation = AuriUICapability(
        id: "nav", description: "Open another screen", acceptsFormInput: true
    )
    public static let send = AuriUICapability(
        id: "send", description: "Send input to the host", acceptsFormInput: true
    )
    public static let url = AuriUICapability(id: "url", description: "Open a link")
}

@available(iOS 17.0, macOS 14.0, *)
public enum AuriUITelemetryEvent: Equatable, Sendable {
    case composed(latencyMilliseconds: Int, cacheHit: Bool, sectionCount: Int)
    case failed(latencyMilliseconds: Int, partialSectionCount: Int)
}

/// Services belong to a session or flow, not to a process-wide registry.
/// Rendering local documents needs no service configuration or network access.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public struct AuriUIHostServices {
    public var capabilities: [AuriUICapability]
    public var stream: (@MainActor (AuriUIStreamRequest) -> AsyncThrowingStream<AuriUIStreamEvent, Error>)?
    public var prefetchEnabled: Bool

    private let resolveImage: @MainActor (String, Bool) -> URL?
    private let resolveLookup: @MainActor (String) -> URL?
    private let reportTelemetry: @MainActor (AuriUITelemetryEvent) -> Void

    public init(
        capabilities: [AuriUICapability] = [.navigation, .send, .url],
        stream: (@MainActor (AuriUIStreamRequest) -> AsyncThrowingStream<AuriUIStreamEvent, Error>)? = nil,
        imageURL: @escaping @MainActor (String, Bool) -> URL? = { _, _ in nil },
        lookupURL: @escaping @MainActor (String) -> URL? = { _ in nil },
        onTelemetry: @escaping @MainActor (AuriUITelemetryEvent) -> Void = { _ in },
        prefetchEnabled: Bool = false
    ) {
        self.capabilities = capabilities
        self.stream = stream
        self.resolveImage = imageURL
        self.resolveLookup = lookupURL
        self.reportTelemetry = onTelemetry
        self.prefetchEnabled = prefetchEnabled
    }

    public func imageURL(query: String, full: Bool = false) -> URL? {
        resolveImage(query, full)
    }

    public func lookupURL(query: String) -> URL? {
        resolveLookup(query)
    }

    public func onTelemetry(_ event: AuriUITelemetryEvent) {
        reportTelemetry(event)
    }

    public func canPerform(_ action: AuriUIAction) -> Bool {
        capabilities.contains { capability in
            guard capability.id == action.capabilityID, capability.isAvailable() else { return false }
            if case .hostCapability = action {
                return capability.exposure == .hostOnly
            }
            return capability.exposure == .composer
        }
    }

    public func canSubmitForm(to capabilityID: String) -> Bool {
        capabilities.contains {
            $0.id == capabilityID && $0.exposure == .composer && $0.acceptsFormInput && $0.isAvailable()
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public enum AuriUICompositionError: LocalizedError, Equatable, Sendable {
    case missingProvider
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .missingProvider: "No screen provider is configured."
        case .emptyResult: "The screen provider did not return a complete, renderable document."
        }
    }
}
#endif
