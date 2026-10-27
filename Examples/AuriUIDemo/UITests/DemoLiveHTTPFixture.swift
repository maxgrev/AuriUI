import Foundation
import Network

/// A loopback HTTP server in the test runner. The app uses the public network
/// adapter and real URLSession requests; no transport is replaced in the app.
final class DemoLiveHTTPFixture: @unchecked Sendable {
    enum Scenario: Sendable { case success, failureThenSuccess, slowThenSuccess, markdownImages }

    struct Request: Sendable {
        let path: String
        let headers: [String: String]
        let body: Data
    }

    static let token = "demo-fixture-access-token-1234567890"
    static let prompt = "Create fixture lunch."

    private let listener: NWListener
    private let queue = DispatchQueue(label: "org.auriui.demo.http-fixture")
    private let lock = NSLock()
    private let scenario: Scenario
    private var capturedRequests: [Request] = []
    // Listener and connection state are confined to queue.
    private var didResumeStart = false
    private var connections: [FixtureConnection] = []

    var requests: [Request] { lock.withLock { capturedRequests } }

    init(scenario: Scenario = .success) throws {
        self.scenario = scenario
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.didResumeStart else { return }
                switch state {
                case .ready:
                    self.didResumeStart = true
                    guard let port = self.listener.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)") else {
                        continuation.resume(throwing: URLError(.badURL))
                        return
                    }
                    continuation.resume(returning: url)
                case .failed(let error):
                    self.didResumeStart = true
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let handler = FixtureConnection(connection: connection, queue: self.queue) { [weak self] request in
                    self?.response(to: request) ?? .init(status: 503, chunks: [])
                }
                self.connections.append(handler)
                handler.start()
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        queue.async { [self] in
            for connection in connections { connection.cancel() }
            connections.removeAll()
        }
    }

    private func response(to request: Request) -> FixtureResponse {
        let attempt = lock.withLock {
            capturedRequests.append(request)
            return capturedRequests.count
        }
        guard request.path == "/screen" else { return .init(status: 404, chunks: []) }
        guard request.headers["authorization"] == "Bearer \(Self.token)" else {
            return .init(status: 401, chunks: [])
        }
        if scenario == .failureThenSuccess && attempt == 1 {
            return .init(status: 503, chunks: [])
        }
        let requestObject = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
        let brief = requestObject?["brief"] as? String ?? ""
        let isRoot = brief == Self.prompt
        let text: String
        if scenario == .markdownImages, let port = listener.port {
            text = """
            aui 1
            screen markdown_images "Markdown images"
            header 📝 "Markdown image policy"
            intro "![Block image](http://127.0.0.1:\(port.rawValue)/block-image)"
            intro "Before ![Inline image](http://127.0.0.1:\(port.rawValue)/inline-image) after"
            """
        } else {
            text = isRoot ? Self.rootDocument : Self.childDocument
        }
        let prefix = text.split(separator: "\n").prefix(3).joined(separator: "\n") + "\n"
        return .init(status: 200, chunks: [
            .init(delay: 0, data: Self.event("status", ["phase": "designing"])),
            .init(delay: 0.05, data: Self.event("aui.delta", ["text": prefix])),
            .init(delay: scenario == .slowThenSuccess && attempt == 1 ? 30 : 0.15,
                  data: Self.event("aui.document", ["text": text, "screen_id": isRoot ? "live-lunch" : "live-child"]))
        ])
    }

    private static func event(_ name: String, _ payload: [String: String]) -> Data {
        let json = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return Data("event: \(name)\ndata: \(String(decoding: json, as: UTF8.self))\n\n".utf8)
    }

    private static let rootDocument = """
    aui 1
    screen live-lunch "Live lunch"
    header 🥪 "Build your lunch" "Generated over HTTP"
    state base:8.50 cur:USD
    list "Bread" pick:bread
    item 🍞 "Sourdough" val:sourdough price:0 sel
    list "Extras" multi
    item 🥑 "Avocado" val:avocado price:1.25
    button primary "Review {total}" @send("Lunch: {selections}. Total {total}.")
    button "Next step" @nav("Lunch: {selections}. Total {total}.")
    """

    private static let childDocument = """
    aui 1
    screen live-child "Live child"
    header 🧭 "Your next screen" "Also generated over HTTP"
    button primary "Send child result" @send("The child screen is complete.")
    """
}

private struct FixtureResponse: Sendable {
    struct Chunk: Sendable { let delay: TimeInterval; let data: Data }
    let status: Int
    let chunks: [Chunk]
}

/// All mutable state is used on the server's serial queue.
private final class FixtureConnection: @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue
    let respond: @Sendable (DemoLiveHTTPFixture.Request) -> FixtureResponse
    var buffer = Data()
    var cancelled = false

    init(connection: NWConnection, queue: DispatchQueue, respond: @escaping @Sendable (DemoLiveHTTPFixture.Request) -> FixtureResponse) {
        self.connection = connection
        self.queue = queue
        self.respond = respond
    }

    func start() {
        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        cancelled = true
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, complete, error in
            if let data { buffer.append(data) }
            guard buffer.count <= 65_536, error == nil else { cancel(); return }
            if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let lines = String(decoding: buffer[..<boundary.lowerBound], as: UTF8.self)
                    .components(separatedBy: "\r\n")
                let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                }
                let length = Int(headers["content-length"] ?? "0") ?? 0
                let body = buffer[boundary.upperBound...]
                if body.count >= length {
                    let response = respond(.init(path: path, headers: headers, body: Data(body.prefix(length))))
                    send(response)
                    return
                }
            }
            if complete { cancel() } else { receive() }
        }
    }

    private func send(_ response: FixtureResponse) {
        let contentType = response.status == 200 ? "text/event-stream" : "application/json"
        let header = "HTTP/1.1 \(response.status) Fixture\r\nContent-Type: \(contentType)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [self] error in
            guard error == nil else { cancel(); return }
            sendChunk(0, response: response)
        })
    }

    private func sendChunk(_ index: Int, response: FixtureResponse) {
        guard !cancelled else { return }
        guard index < response.chunks.count else {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [self] _ in cancel() })
            return
        }
        let chunk = response.chunks[index]
        queue.asyncAfter(deadline: .now() + chunk.delay) { [self] in
            guard !cancelled else { return }
            connection.send(content: chunk.data, completion: .contentProcessed { [self] error in
                guard error == nil else { cancel(); return }
                sendChunk(index + 1, response: response)
            })
        }
    }
}
