#if os(iOS) || os(macOS)
import AuriUI
@testable import AuriUIRenderer
import Foundation
import Testing

@Suite("Renderer input validation", .enabled(if: supportsRendererInputs))
struct RendererInputTests {
    @Test("Malformed host-authored slider bounds never construct a control")
    func invalidSliderBounds() {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let ranges: [(Decimal, Decimal)] = [(10, 5), (5, 5), (.nan, 10), (0, .nan)]
        for (minimum, maximum) in ranges {
            let field = slider(minimum: minimum, maximum: maximum)
            #expect(AuriUISliderConfiguration(field: field) == nil)
        }
    }

    @Test("Slider increments must be finite and positive")
    func invalidSliderSteps() {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        for step in [Decimal(0), Decimal(-1), Decimal.nan] {
            let field = slider(minimum: 0, maximum: 10, step: step)
            #expect(AuriUISliderConfiguration(field: field) == nil)
        }
    }

    @Test("Valid bounds survive and invalid stored values stay inside them")
    func sliderBindingValues() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let configuration = try #require(AuriUISliderConfiguration(
            field: slider(minimum: -10, maximum: 20, step: Decimal(5) / 10)
        ))
        #expect(configuration.range == -10...20)
        #expect(configuration.step == 0.5)
        #expect(configuration.value(from: "7.5") == 7.5)
        #expect(configuration.value(from: "-11") == -10)
        #expect(configuration.value(from: "25") == 20)
        for text in ["", "invalid", "nan", "inf", "-inf"] {
            #expect(configuration.value(from: text) == -10)
        }
    }

    @Test("Image size limits reject advertised and streamed oversized bodies", arguments: ["advertised", "streamed"])
    func oversizedImagesCancelTransport(mode: String) async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let session = imageSession()
        let url = URL(string: "https://\(UUID().uuidString).example/\(mode)")!
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            session.invalidateAndCancel()
        }
        defer {
            timeout.cancel()
            session.invalidateAndCancel()
            ImageURLProtocol.cancellations.remove(url)
        }
        let cache = VisualImageCache(session: session)
        await #expect(throws: VisualImageCache.CacheError.payloadTooLarge) {
            _ = try await cache.data(for: url)
        }
        if mode == "streamed" {
            let deadline = ContinuousClock.now + .seconds(2)
            while !ImageURLProtocol.cancellations.contains(url) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(ImageURLProtocol.cancellations.contains(url))
        }
    }

    @Test("Image downloads preserve HTTP and content-type validation", arguments: ["status", "content-type"])
    func invalidImageResponse(mode: String) async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let session = imageSession()
        defer { session.invalidateAndCancel() }
        let cache = VisualImageCache(session: session)
        let url = URL(string: "https://\(UUID().uuidString).example/\(mode)")!
        let expected: VisualImageCache.CacheError = mode == "status" ? .invalidResponse : .invalidImagePayload
        await #expect(throws: expected) {
            _ = try await cache.data(for: url)
        }
    }

    @Test("Valid remote and local image bytes remain available")
    func validImages() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let session = imageSession()
        defer { session.invalidateAndCancel() }
        let cache = VisualImageCache(session: session)
        let remoteURL = URL(string: "https://\(UUID().uuidString).example/valid")!
        #expect(try await cache.data(for: remoteURL) == ImageURLProtocol.png)
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try ImageURLProtocol.png.write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }
        #expect(try await cache.data(for: localURL) == ImageURLProtocol.png)
    }

    private func imageSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func slider(minimum: Decimal, maximum: Decimal, step: Decimal = 1) -> AuriUIFormField {
        AuriUIFormField(
            id: "amount",
            kind: .slider,
            label: "Amount",
            minimum: minimum,
            maximum: maximum,
            step: step
        )
    }
}

private var supportsRendererInputs: Bool {
    if #available(iOS 17.0, macOS 14.0, *) { return true }
    return false
}

// URLProtocol callbacks run off the test task; the lock protects every access.
private final class ImageCancellations: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: Set<URL> = []
    func contains(_ url: URL) -> Bool { lock.withLock { urls.contains(url) } }
    func insert(_ url: URL) { _ = lock.withLock { urls.insert(url) } }
    func remove(_ url: URL) { _ = lock.withLock { urls.remove(url) } }
}

private final class ImageURLProtocol: URLProtocol, @unchecked Sendable {
    static let cancellations = ImageCancellations()
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM2sAAAAASUVORK5CYII=")!

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mode = request.url!.lastPathComponent
        let oversizedCount = 20 * 1_024 * 1_024 + 1
        var headers = ["Content-Type": mode == "content-type" ? "application/json" : "image/png"]
        if mode == "advertised" { headers["Content-Length"] = String(oversizedCount) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: mode == "status" ? 503 : 200,
            httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // A large declared length must fail even when few bytes arrive.
        if mode == "advertised" {
            client?.urlProtocol(self, didLoad: Data([0]))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        // This response never finishes: crossing the byte limit must reject
        // and cancel transport without waiting for EOF or the remaining body.
        if mode == "streamed" {
            client?.urlProtocol(self, didLoad: Data(repeating: 0, count: oversizedCount))
            return
        }
        client?.urlProtocol(self, didLoad: Self.png)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        if let url = request.url, ["advertised", "streamed"].contains(url.lastPathComponent) {
            Self.cancellations.insert(url)
        }
    }
}
#endif
