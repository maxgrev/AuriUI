import Foundation
import Testing
@testable import AuriUIDemo

@Suite("Live demo setup")
struct DemoLiveConfigurationTests {
    private let token = "demo-fixture-access-token-1234567890"

    @Test("Trims setup fields without changing credentials or prompt content")
    func validSetup() throws {
        let config = try DemoLiveConfiguration(
            endpoint: "  https://screens.example.com/\n",
            accessToken: " \(token)\n",
            prompt: "  Make a lunch order with a $9 sandwich.\n"
        )
        #expect(config.endpoint.absoluteString == "https://screens.example.com/")
        #expect(config.accessToken == token)
        #expect(config.prompt == "Make a lunch order with a $9 sandwich.")
    }

    @Test("Rejects remote cleartext URLs and credentials embedded in URLs", arguments: [
        "", "screens.example.com", "http://screens.example.com", "file:///tmp/screen",
        "https://user:secret@screens.example.com", "https://screens.example.com?key=secret",
        "https://screens.example.com#secret", "http://localhost.attacker.example"
    ])
    func unsafeEndpoint(_ endpoint: String) {
        #expect(throws: DemoLiveConfiguration.ValidationError.self) {
            try DemoLiveConfiguration(endpoint: endpoint, accessToken: token, prompt: "A lunch menu")
        }
    }

    @Test("Allows HTTP only for local development", arguments: [
        "http://127.0.0.1:8787", "http://localhost:8787", "http://[::1]:8787"
    ])
    func localEndpoint(_ endpoint: String) throws {
        _ = try DemoLiveConfiguration(endpoint: endpoint, accessToken: token, prompt: "A lunch menu")
    }

    @Test("Rejects missing token and header injection", arguments: ["", " \n", "part one", "part\r\nInjected: value"])
    func invalidToken(_ token: String) {
        #expect(throws: DemoLiveConfiguration.ValidationError.self) {
            try DemoLiveConfiguration(endpoint: "https://screens.example.com", accessToken: token, prompt: "A lunch menu")
        }
    }

    @Test("Uses the backend's UTF-16 prompt limit, including emoji")
    func promptLimit() throws {
        _ = try DemoLiveConfiguration(endpoint: "https://screens.example.com", accessToken: token, prompt: String(repeating: "🧑", count: 4_000))
        for prompt in [" \n", String(repeating: "🧑", count: 4_001)] {
            #expect(throws: DemoLiveConfiguration.ValidationError.self) {
                try DemoLiveConfiguration(endpoint: "https://screens.example.com", accessToken: token, prompt: prompt)
            }
        }
    }
}
