#if os(iOS) || os(macOS)
import AuriUI
import AuriUIRenderer
import Foundation
import Testing

@MainActor
@Suite("HTTP generation adapter")
struct HTTPClientTests {
    @Test("Requests refresh authorization and advertise only usable composer capabilities")
    func requestContract() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let fixture = HTTPFixture(replies: [.document, .document])
        defer { fixture.close() }
        let token = TestAccessToken(value: "first")
        let client = try AuriUIHTTPClient(baseURL: fixture.url.appendingPathComponent("api"), session: fixture.session, locale: "fr_FR") {
            ["Authorization": "Bearer \(token.value)", "X-App-User": "user-42"]
        }
        let capabilities: [AuriUICapability] = [
            .send,
            .init(id: "host.secret", description: "Host only", exposure: .hostOnly),
            .init(id: "nav", description: "Unavailable", isAvailable: { false }),
        ]
        let services = client.makeServices(capabilities: capabilities)
        let stream = try #require(services.stream)
        _ = try await collect(stream(.init(brief: "A lunch plan", grounded: false)))
        token.value = "refreshed"
        _ = try await collect(stream(.init(brief: "Retry", grounded: true)))
        let requests = fixture.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.path == "/api/screen")
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer first")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer refreshed")
        #expect(requests[0].value(forHTTPHeaderField: "X-App-User") == "user-42")
        #expect(requests[0].value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(try JSONSerialization.jsonObject(with: fixture.bodies[0]) as? [String: Any])
        #expect(body["brief"] as? String == "A lunch plan")
        #expect(body["grounded"] as? Bool == false)
        #expect(body["locale"] as? String == "fr_FR")
        let advertised = try #require(body["capabilities"] as? [[String: Any]])
        #expect(advertised.count == 1)
        #expect(advertised[0]["id"] as? String == "send")
        #expect(advertised[0]["acceptsFormInput"] as? Bool == true)
        #expect((body["components"] as? [String])?.contains("form") == true)
        let secondBody = try #require(try JSONSerialization.jsonObject(with: fixture.bodies[1]) as? [String: Any])
        #expect(secondBody["grounded"] as? Bool == true)
    }

    @Test("Form vocabulary is omitted when no available capability accepts input")
    func componentContract() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let fixture = HTTPFixture(replies: [.document])
        defer { fixture.close() }
        let client = try AuriUIHTTPClient(baseURL: fixture.url, session: fixture.session)
        _ = try await collect(client.stream(.init(brief: "Links"), capabilities: [.url]))
        let body = try #require(try JSONSerialization.jsonObject(with: fixture.bodies[0]) as? [String: Any])
        #expect((body["components"] as? [String])?.contains("form") == false)
    }

    @Test("SSE framing survives byte-sized chunks, Unicode, CRLF, comments and multiline data")
    func streamedEvents() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let deltaJSON = String(decoding: try JSONEncoder().encode("aui 1\nintro \"Café ☕\"\n"), as: UTF8.self)
        let documentJSON = String(decoding: try JSONEncoder().encode("aui 1\nintro \"Café ☕\""), as: UTF8.self)
        let wire = """
        \u{FEFF}:keepalive\r
        event: status\r
        data: {"phase":"designing"}\r
        \r
        event: future.event\r
        data: not JSON, intentionally ignored\r
        \r
        event: aui.resources\r
        data: {"R1":{"url":"https://example.com/a"},"r2":"https://example.com/b"}\r
        \r
        event: aui.delta\r
        data: {"text":\r
        data: \(deltaJSON)}\r
        \r
        event: aui.document\r
        data: {"text":\(documentJSON), "screen_id":"screen-42"}\r
        \r

        """
        let fixture = HTTPFixture(replies: [.init(chunks: wire.utf8.map { Data([$0]) })])
        defer { fixture.close() }
        let client = try AuriUIHTTPClient(baseURL: fixture.url, session: fixture.session)
        let events = try await collect(client.stream(.init(brief: "Coffee")))
        #expect(events == [
            .designing,
            .resources(["r1": URL(string: "https://example.com/a")!, "r2": URL(string: "https://example.com/b")!]),
            .delta("aui 1\nintro \"Café ☕\"\n"),
            .document(text: "aui 1\nintro \"Café ☕\"", screenID: "screen-42"),
        ])
    }

    @Test("A delta reaches the caller before the server closes, and cancellation stops transport")
    func incrementalCancellation() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let fixture = HTTPFixture(replies: [.init(text: event("aui.delta", ["text": "aui 1\nintro \"Partial\"\n"]), finishes: false)])
        defer { fixture.close() }
        let client = try AuriUIHTTPClient(baseURL: fixture.url, session: fixture.session)
        var delivered: [AuriUIStreamEvent] = []
        let consumer = Task {
            for try await event in client.stream(.init(brief: "Slow")) { delivered.append(event) }
        }
        try await waitUntil { !delivered.isEmpty }
        #expect(delivered == [.delta("aui 1\nintro \"Partial\"\n")])
        #expect(fixture.stopCount == 0)
        consumer.cancel()
        _ = await consumer.result
        try await waitUntil { fixture.stopCount == 1 }
    }

    @Test("A final document finishes and cancels an otherwise open SSE connection")
    func authoritativeCompletion() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let fixture = HTTPFixture(replies: [.init(text: event("aui.document", ["text": completeDocument]), finishes: false)])
        defer { fixture.close() }
        let client = try AuriUIHTTPClient(baseURL: fixture.url, session: fixture.session)
        let events = try await collect(client.stream(.init(brief: "Complete")))
        #expect(events == [.document(text: completeDocument, screenID: nil)])
        try await waitUntil { fixture.stopCount == 1 }
    }

    @Test("Malformed, failed, unsupported and truncated responses never commit", arguments: FailureCase.allCases)
    func failures(kind: FailureCase) async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let fixture = HTTPFixture(replies: [kind.reply])
        defer { fixture.close() }
        let client = try AuriUIHTTPClient(baseURL: fixture.url, session: fixture.session)
        var documentCount = 0
        do {
            for try await event in client.stream(.init(brief: "Failure")) {
                if case .document = event { documentCount += 1 }
            }
            Issue.record("Expected \(kind) to fail")
        } catch {
            #expect(error as? AuriUIHTTPError == kind.expected)
            #expect(!error.localizedDescription.contains("secret-token"))
        }
        #expect(documentCount == 0)
    }

    @Test("Invalid backend URLs fail before sending credentials", arguments: [
        "http://example.com", "ftp://example.com", "https://user:secret@example.com",
        "https://example.com?token=secret", "https://example.com#fragment", "file:///tmp/backend",
    ])
    func invalidURL(text: String) throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        #expect(throws: AuriUIHTTPError.invalidBaseURL) {
            try AuriUIHTTPClient(baseURL: URL(string: text)!)
        }
    }

    @Test("HTTPS and explicit loopback development endpoints are accepted", arguments: [
        "https://example.com/backend/", "http://localhost:8787", "http://127.0.0.1:8787", "http://[::1]:8787",
    ])
    func validURL(text: String) throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        _ = try AuriUIHTTPClient(baseURL: URL(string: text)!)
    }

    @Test("Header injection fails without a network request")
    func invalidHeader() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let fixture = HTTPFixture(replies: [.document])
        defer { fixture.close() }
        let client = try AuriUIHTTPClient(baseURL: fixture.url, session: fixture.session) {
            ["Authorization": "Bearer safe\r\nX-Injected: unsafe"]
        }
        do {
            _ = try await collect(client.stream(.init(brief: "Unsafe header")))
            Issue.record("Expected invalid header")
        } catch { #expect(error as? AuriUIHTTPError == .invalidHeader) }
        #expect(fixture.requests.isEmpty)
    }
}

private let completeDocument = "aui 1\nintro \"Complete\""

@MainActor
private final class TestAccessToken {
    var value: String
    init(value: String) { self.value = value }
}

private func event(_ name: String, _ payload: [String: String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return "event: \(name)\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
}

@available(iOS 17.0, macOS 14.0, *)
private func collect(_ stream: AsyncThrowingStream<AuriUIStreamEvent, Error>) async throws -> [AuriUIStreamEvent] {
    var result: [AuriUIStreamEvent] = []
    for try await event in stream { result.append(event) }
    return result
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "Timed out waiting for transport")
}

enum FailureCase: String, CaseIterable, Sendable {
    case unauthorized, serverHTTP, wrongContentType, malformedJSON, missingField, unsafeResource
    case truncated, prematureDone, partialFinalEvent, invalidDocument, unsupportedVersion, serverEvent, oversizedEvent, oversizedDocument

    var reply: HTTPReply {
        switch self {
        case .unauthorized: .init(text: "secret-token", status: 401)
        case .serverHTTP: .init(text: "secret-token", status: 503)
        case .wrongContentType: .init(text: "<html>Sign in</html>", mime: "text/html")
        case .malformedJSON: .init(text: "event: aui.delta\ndata: not-json\n\n")
        case .missingField: .init(text: event("aui.delta", ["wrong": "value"]))
        case .unsafeResource: .init(text: event("aui.resources", ["r1": "file:///tmp/secret"]))
        case .truncated: .init(text: event("aui.delta", ["text": completeDocument]))
        case .prematureDone: .init(text: event("done", ["outcome": "screen"]))
        case .partialFinalEvent: .init(text: String(event("aui.document", ["text": completeDocument]).dropLast()))
        case .invalidDocument: .init(text: event("aui.document", ["text": "not a screen"]))
        case .unsupportedVersion: .init(text: event("aui.document", ["text": "aui 99\nintro \"Future\""]))
        case .serverEvent: .init(text: event("error", ["message": "secret-token"]))
        case .oversizedEvent: .init(text: "event: unknown\ndata: " + String(repeating: "a", count: 2_097_153))
        case .oversizedDocument: .init(text: event("aui.document", ["text": "aui 1\nintro \"" + String(repeating: "a", count: 1_048_577) + "\""]))
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    var expected: AuriUIHTTPError {
        switch self {
        case .unauthorized: .httpStatus(401)
        case .serverHTTP: .httpStatus(503)
        case .wrongContentType: .invalidContentType
        case .malformedJSON, .missingField: .malformedEvent("aui.delta")
        case .unsafeResource: .malformedEvent("aui.resources")
        case .truncated, .prematureDone, .partialFinalEvent: .incompleteStream
        case .invalidDocument: .invalidDocument
        case .unsupportedVersion: .unsupportedDocument(.unsupportedVersion(99))
        case .serverEvent: .serverError
        case .oversizedEvent, .oversizedDocument: .streamTooLarge
        }
    }
}

struct HTTPReply: Sendable {
    var chunks: [Data]
    var status = 200
    var mime = "text/event-stream; charset=utf-8"
    var finishes = true

    init(text: String, status: Int = 200, mime: String = "text/event-stream; charset=utf-8", finishes: Bool = true) {
        self.chunks = [Data(text.utf8)]
        self.status = status
        self.mime = mime
        self.finishes = finishes
    }

    init(chunks: [Data]) { self.chunks = chunks }
    static var document: Self { .init(text: event("aui.document", ["text": completeDocument])) }
}

// URLProtocol callbacks use Foundation's queue; this fixture protects every
// shared mutable value with a lock. Each test uses its own unique host/session.
private final class HTTPFixture: @unchecked Sendable {
    let url = URL(string: "https://\(UUID().uuidString.lowercased()).example")!
    let session: URLSession
    private let lock = NSLock()
    private var replies: [HTTPReply]
    private var capturedRequests: [URLRequest] = []
    private var capturedBodies: [Data] = []
    private var stopped = 0

    init(replies: [HTTPReply]) {
        self.replies = replies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        session = URLSession(configuration: configuration)
        FixtureURLProtocol.registry.insert(self)
    }

    var requests: [URLRequest] { lock.withLock { capturedRequests } }
    var bodies: [Data] { lock.withLock { capturedBodies } }
    var stopCount: Int { lock.withLock { stopped } }
    func didStop() { lock.withLock { stopped += 1 } }
    func close() {
        session.invalidateAndCancel()
        FixtureURLProtocol.registry.remove(self)
    }

    func next(_ request: URLRequest) -> HTTPReply {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        return lock.withLock {
            capturedRequests.append(request)
            capturedBodies.append(body)
            return replies.removeFirst()
        }
    }
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = Registry()
    private var fixture: HTTPFixture?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let fixture = Self.registry.find(request.url?.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        self.fixture = fixture
        let reply = fixture.next(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": reply.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in reply.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if reply.finishes { client?.urlProtocolDidFinishLoading(self) }
    }

    override func stopLoading() { fixture?.didStop() }

    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var fixtures: [String: HTTPFixture] = [:]
        func insert(_ fixture: HTTPFixture) { lock.withLock { fixtures[fixture.url.host!] = fixture } }
        func remove(_ fixture: HTTPFixture) { _ = lock.withLock { fixtures.removeValue(forKey: fixture.url.host!) } }
        func find(_ host: String?) -> HTTPFixture? { lock.withLock { host.flatMap { fixtures[$0] } } }
    }
}
#endif
