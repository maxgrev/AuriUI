#if os(iOS) || os(macOS)
import AuriUI
import Foundation

/// Connects the renderer to an AuriUI-compatible HTTP backend.
///
/// `baseURL` is the Worker origin (or a path prefix), without `/screen`.
/// Headers are requested again for every composition, including retries and
/// child screens. Keep provider API keys on the server; supply your own app's
/// authorization here. The reference backend requires `grounded: false`.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class AuriUIHTTPClient {
    private let endpoint: URL
    private let session: URLSession
    private let locale: String
    private let headers: @MainActor @Sendable () async throws -> [String: String]

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        locale: String = Locale.current.identifier,
        headers: @escaping @MainActor @Sendable () async throws -> [String: String] = { [:] }
    ) throws {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.scheme?.lowercased() == "https"
                || (components.scheme?.lowercased() == "http"
                    && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw AuriUIHTTPError.invalidBaseURL
        }
        self.endpoint = baseURL.appendingPathComponent("screen")
        self.session = session
        self.locale = locale
        self.headers = headers
    }

    public func makeServices(
        capabilities: [AuriUICapability] = [.navigation, .send, .url],
        imageURL: @escaping @MainActor (String, Bool) -> URL? = { _, _ in nil },
        lookupURL: @escaping @MainActor (String) -> URL? = { _ in nil },
        onTelemetry: @escaping @MainActor (AuriUITelemetryEvent) -> Void = { _ in },
        prefetchEnabled: Bool = false
    ) -> AuriUIHostServices {
        AuriUIHostServices(
            capabilities: capabilities,
            stream: { [self] in stream($0, capabilities: capabilities) },
            imageURL: imageURL,
            lookupURL: lookupURL,
            onTelemetry: onTelemetry,
            prefetchEnabled: prefetchEnabled
        )
    }

    public func stream(
        _ request: AuriUIStreamRequest,
        capabilities: [AuriUICapability] = [.navigation, .send, .url]
    ) -> AsyncThrowingStream<AuriUIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let available = capabilities.filter { $0.exposure == .composer && $0.isAvailable() }
                    let payload = RequestBody(
                        brief: request.brief,
                        grounded: request.grounded,
                        locale: locale,
                        capabilities: available.map {
                            Capability(id: $0.id, description: $0.description, acceptsFormInput: $0.acceptsFormInput)
                        },
                        components: AuriUIContract.advertisedComponentIDs.filter {
                            $0 != "form" || available.contains(where: \.acceptsFormInput)
                        }
                    )
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = 90
                    for (name, value) in try await headers() {
                        guard !name.isEmpty,
                              name.unicodeScalars.allSatisfy({ Self.headerNameCharacters.contains($0) }),
                              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                            throw AuriUIHTTPError.invalidHeader
                        }
                        urlRequest.setValue(value, forHTTPHeaderField: name)
                    }
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONEncoder().encode(payload)
                    try Task.checkCancellation()
                    try await Self.receive(urlRequest, session: session, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static let headerNameCharacters = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private struct RequestBody: Encodable {
        let brief: String
        let grounded: Bool
        let locale: String
        let capabilities: [Capability]
        let components: [String]
    }

    private struct Capability: Encodable {
        let id: String
        let description: String
        let acceptsFormInput: Bool
    }

    // Parsing stays off the main actor. A single event is bounded before JSON
    // decoding, and a single line is bounded before UTF-8 decoding.
    nonisolated private static func receive(
        _ request: URLRequest,
        session: URLSession,
        continuation: AsyncThrowingStream<AuriUIStreamEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request, delegate: RejectRedirects())
        defer { bytes.task.cancel() }
        try await withTaskCancellationHandler {
            guard let response = response as? HTTPURLResponse else { throw AuriUIHTTPError.invalidResponse }
            guard (200...299).contains(response.statusCode) else {
                // Error bodies can contain credentials or be unbounded. Never
                // consume or surface them; the HTTP status is safe to report.
                throw AuriUIHTTPError.httpStatus(response.statusCode)
            }
            guard response.mimeType?.lowercased() == "text/event-stream" else {
                throw AuriUIHTTPError.invalidContentType
            }
            var decoder = EventDecoder()
            var deltaBytes = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                if let event = try decoder.consume(byte) {
                    if try deliver(event, deltaBytes: &deltaBytes, continuation: continuation) { return }
                }
            }
            // SSE only dispatches events terminated by a blank line. An EOF
            // cannot promote a partial event or delta into a committed screen.
            throw AuriUIHTTPError.incompleteStream
        } onCancel: {
            bytes.task.cancel()
        }
    }

    nonisolated private static func deliver(
        _ event: EventDecoder.Event,
        deltaBytes: inout Int,
        continuation: AsyncThrowingStream<AuriUIStreamEvent, Error>.Continuation
    ) throws -> Bool {
        let known = ["status", "aui.delta", "aui.resources", "aui.document", "error", "done"]
        guard known.contains(event.name) else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: event.data),
              let payload = object as? [String: Any] else {
            throw AuriUIHTTPError.malformedEvent(event.name)
        }
        switch event.name {
        case "status":
            guard payload["phase"] is String else { throw AuriUIHTTPError.malformedEvent(event.name) }
            continuation.yield(.designing)
        case "aui.delta":
            guard let text = payload["text"] as? String else { throw AuriUIHTTPError.malformedEvent(event.name) }
            deltaBytes += text.utf8.count
            guard deltaBytes <= maximumDocumentBytes else { throw AuriUIHTTPError.streamTooLarge }
            continuation.yield(.delta(text))
        case "aui.resources":
            guard payload.count <= 512 else { throw AuriUIHTTPError.streamTooLarge }
            var resources: [String: URL] = [:]
            for (id, value) in payload {
                let text = (value as? String) ?? (value as? [String: Any])?["url"] as? String
                guard let text, let url = URL(string: text),
                      let host = url.host, !host.isEmpty,
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      url.user == nil, url.password == nil else {
                    throw AuriUIHTTPError.malformedEvent(event.name)
                }
                resources[id.lowercased()] = url
            }
            continuation.yield(.resources(resources))
        case "aui.document":
            guard let text = payload["text"] as? String,
                  payload["screen_id"] == nil || payload["screen_id"] is NSNull || payload["screen_id"] is String else {
                throw AuriUIHTTPError.malformedEvent(event.name)
            }
            guard text.utf8.count <= maximumDocumentBytes else { throw AuriUIHTTPError.streamTooLarge }
            var parser = AuriUIStreamingParser()
            parser.consume(text)
            parser.finish()
            if let failure = parser.failure { throw AuriUIHTTPError.unsupportedDocument(failure) }
            guard parser.document.isRenderable else { throw AuriUIHTTPError.invalidDocument }
            continuation.yield(.document(text: text, screenID: payload["screen_id"] as? String))
            // The authoritative document is terminal. All resources precede
            // it; closing here also cancels a server that forgets to close SSE.
            return true
        case "error":
            guard payload["message"] is String else { throw AuriUIHTTPError.malformedEvent(event.name) }
            throw AuriUIHTTPError.serverError
        case "done":
            guard payload["outcome"] is String else { throw AuriUIHTTPError.malformedEvent(event.name) }
            throw AuriUIHTTPError.incompleteStream
        default:
            break
        }
        return false
    }

    nonisolated private static let maximumDocumentBytes = 1_048_576

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            // Authorization and host-defined headers must never move to a
            // redirect destination. Configure the actual backend URL instead.
            completionHandler(nil)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public enum AuriUIHTTPError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case invalidHeader
    case invalidResponse
    case httpStatus(Int)
    case invalidContentType
    case malformedEvent(String)
    case streamTooLarge
    case incompleteStream
    case serverError
    case invalidDocument
    case unsupportedDocument(AuriUIParsingFailure)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "Use an HTTPS backend URL without credentials, query, or fragment. HTTP is allowed only on localhost."
        case .invalidHeader: "A request header contains invalid characters."
        case .invalidResponse: "The backend did not return an HTTP response."
        case .httpStatus(401), .httpStatus(403): "The backend rejected your authorization. Check your access token."
        case .httpStatus(let status): "The backend rejected the request (HTTP \(status))."
        case .invalidContentType: "The backend did not return an AuriUI event stream."
        case .malformedEvent(let name): "The backend returned an invalid \(name) event."
        case .streamTooLarge: "The backend response exceeds the supported size."
        case .incompleteStream: "The stream ended before a complete screen arrived."
        case .serverError: "The backend could not generate a screen. Try again."
        case .invalidDocument: "The backend returned an empty or invalid screen."
        case .unsupportedDocument(let failure): failure.localizedDescription
        }
    }
}

/// Minimal SSE framing. Handles UTF-8 split across chunks, CR/LF/CRLF,
/// comments, repeated data fields, and the optional initial UTF-8 BOM.
@available(iOS 17.0, macOS 14.0, *)
private struct EventDecoder {
    struct Event {
        let name: String
        let data: Data
    }

    private var line: [UInt8] = []
    private var name = "message"
    private var data = Data()
    private var hasData = false
    private var afterCR = false
    private var firstLine = true
    private var eventBytes = 0
    private var totalBytes = 0

    mutating func consume(_ byte: UInt8) throws -> Event? {
        totalBytes += 1
        eventBytes += 1
        guard eventBytes <= 2_097_152, totalBytes <= 4_194_304 else { throw AuriUIHTTPError.streamTooLarge }
        if afterCR {
            afterCR = false
            if byte == 10 { return nil }
        }
        if byte == 10 || byte == 13 {
            afterCR = byte == 13
            return try finishLine()
        }
        line.append(byte)
        return nil
    }

    private mutating func finishLine() throws -> Event? {
        defer { line.removeAll(keepingCapacity: true) }
        if firstLine {
            firstLine = false
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        guard let text = String(bytes: line, encoding: .utf8) else {
            throw AuriUIHTTPError.malformedEvent("UTF-8")
        }
        if text.isEmpty {
            defer {
                name = "message"
                data.removeAll(keepingCapacity: true)
                hasData = false
                eventBytes = 0
            }
            return hasData ? Event(name: name, data: data) : nil
        }
        if text.first == ":" { return nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = parts[0]
        var value = parts.count == 2 ? parts[1] : ""
        if value.first == " " { value = value.dropFirst() }
        switch field {
        case "event": name = String(value)
        case "data":
            if hasData { data.append(10) }
            data.append(contentsOf: value.utf8)
            hasData = true
        default: break
        }
        return nil
    }
}
#endif
