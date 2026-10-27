import AuriUIRenderer
import Foundation
import Observation
import SwiftUI

/// Credentials stay in this view's memory. They are never written to disk.
struct DemoLiveView: View {
    @State private var endpoint = ""
    @State private var accessToken = ""
    @State private var prompt = "Create an interactive lunch order. Offer sourdough for $8.50 or a bagel for $9.00, with optional avocado for $1.25 and cheese for $0.75. Show the total and a review button."
    @State private var flow: DemoLiveFlow?
    @State private var path: [String] = []
    @State private var setupError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case endpoint, token, prompt }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Text("Generate a native screen with your own backend.")
                    Text("Deploy the Cloudflare Worker from this package's Backend folder. Set its Cerebras key on the server, then enter the Worker URL and access token here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("https://your-worker.workers.dev", text: $endpoint)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .endpoint)
                        .accessibilityLabel("Worker URL")
                        .accessibilityIdentifier("demo.live.endpoint")
                    SecureField("Backend access token", text: $accessToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .token)
                        .accessibilityIdentifier("demo.live.token")
                } header: {
                    Text("Your backend")
                } footer: {
                    Text("Use the Worker's access token, never your Cerebras API key. These fields stay in memory for this app session. Nothing is saved.")
                }

                Section {
                    TextField("Describe a screen and include its facts", text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focusedField, equals: .prompt)
                        .accessibilityLabel("Screen description")
                        .accessibilityIdentifier("demo.live.prompt")
                } header: {
                    Text("Describe a screen and include its facts")
                } footer: {
                    Text("The reference backend generates screens from your text. It does not search the web or supply images. Generate and navigation buttons send requests to your backend.")
                }

                if let setupError {
                    Section {
                        Text(setupError)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("demo.live.setupError")
                    }
                }

                Section {
                    Button("Generate", systemImage: "sparkles", action: generate)
                        .accessibilityIdentifier("demo.live.generate")
                    Button("Clear connection", role: .destructive) {
                        focusedField = nil
                        flow?.cancelAll()
                        flow = nil
                        endpoint = ""
                        accessToken = ""
                        setupError = nil
                    }
                    .disabled(endpoint.isEmpty && accessToken.isEmpty && flow == nil)
                    .accessibilityIdentifier("demo.live.clear")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Live")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let flow, let session = flow.sessions[id] {
                    DemoLiveSurfaceView(session: session) { brief in
                        let child = flow.child(parent: session, brief: brief)
                        path.append(child.id)
                    }
                }
            }
        }
        .onAppear(perform: loadUITestConfiguration)
    }

    private func generate() {
        focusedField = nil
        do {
            let configuration = try DemoLiveConfiguration(endpoint: endpoint, accessToken: accessToken, prompt: prompt)
            let newFlow = try DemoLiveFlow(configuration: configuration)
            flow?.cancelAll()
            flow = newFlow
            setupError = nil
            path = [newFlow.root.id]
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func loadUITestConfiguration() {
        #if DEBUG
        let process = ProcessInfo.processInfo
        guard flow == nil, endpoint.isEmpty,
              process.arguments.contains("-AuriUIDemoLiveFixture") else { return }
        endpoint = process.environment["AURIUI_DEMO_WORKER_URL"] ?? ""
        accessToken = process.environment["AURIUI_DEMO_ACCESS_TOKEN"] ?? ""
        prompt = process.environment["AURIUI_DEMO_PROMPT"] ?? prompt
        #endif
    }
}

struct DemoLiveConfiguration {
    let endpoint: URL
    let accessToken: String
    let prompt: String

    init(endpoint: String, accessToken: String, prompt: String) throws {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), let host = url.host,
              !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && Self.isLoopback(host)) else {
            throw ValidationError.endpoint
        }
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw ValidationError.token
        }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.utf16.count <= 8_000 else { throw ValidationError.prompt }
        self.endpoint = url
        self.accessToken = token
        self.prompt = prompt
    }

    private static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }

    enum ValidationError: LocalizedError {
        case endpoint, token, prompt

        var errorDescription: String? {
            switch self {
            case .endpoint: "Enter a valid HTTPS Worker URL without credentials, a query, or a fragment. HTTP is supported only on localhost."
            case .token: "Enter your backend access token without spaces."
            case .prompt: "Describe a screen and include its facts. Keep the description within 8,000 characters."
            }
        }
    }
}

/// One store owns this complete live flow, including screens reached via nav.
/// Returning to a screen reuses its session and preserves its edited values.
@MainActor
@Observable
final class DemoLiveFlow {
    let root: AuriUIScreenSession
    private(set) var sessions: [String: AuriUIScreenSession]
    private let store: AuriUISurfaceSessionStore

    init(configuration: DemoLiveConfiguration) throws {
        let token = configuration.accessToken
        let client = try AuriUIHTTPClient(baseURL: configuration.endpoint, headers: {
            ["Authorization": "Bearer \(token)"]
        })
        let services = client.makeServices(capabilities: [.navigation, .send])
        store = AuriUISurfaceSessionStore(services: services)
        root = store.session(parentID: nil, brief: configuration.prompt, grounded: false)
        sessions = [root.id: root]
    }

    func child(parent: AuriUIScreenSession, brief: String) -> AuriUIScreenSession {
        let child = store.session(parentID: parent.id, brief: brief, grounded: false)
        sessions[child.id] = child
        return child
    }

    func cancelAll() {
        for session in sessions.values { session.cancel() }
        store.cancelPendingPrefetches()
    }
}

private struct DemoLiveSurfaceView: View {
    let session: AuriUIScreenSession
    let navigate: (String) -> Void
    @State private var wasCancelled = false
    @State private var lastAction = "Send actions appear here. They do not make another request."

    var body: some View {
        Group {
            if wasCancelled {
                ContentUnavailableView("Generation cancelled", systemImage: "stop.circle", description: Text("Restart to send a new request to your backend."))
                    .navigationTitle(session.title ?? "Live")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                AuriUIScreenView(session: session, onSurfaceAction: handle)
            }
        }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text(status)
                        .font(.caption.weight(.medium))
                        .accessibilityIdentifier("demo.live.status")
                    Spacer()
                    if wasCancelled {
                        Button("Restart") {
                            wasCancelled = false
                            session.retry()
                        }
                        .accessibilityIdentifier("demo.live.restart")
                    } else if session.phase == .composing {
                        Button("Cancel") {
                            session.cancel()
                            wasCancelled = true
                        }
                        .accessibilityIdentifier("demo.live.cancel")
                    }
                }
                .padding(12)
                .background(.bar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DemoActionStatus(message: lastAction)
            }
            .onDisappear {
                // The renderer starts a cancelled composition when it next
                // appears. Keep an interrupted live request stopped until
                // the user explicitly chooses Restart.
                if session.phase == .composing { wasCancelled = true }
                session.cancel()
            }
    }

    private var status: String {
        if wasCancelled { return "Cancelled" }
        switch session.phase {
        case .composing: return "Generating…"
        case .ready: return "Complete"
        case .failed: return "Could not finish · retry below"
        }
    }

    private func handle(_ action: AuriUISurfaceAction) {
        switch action {
        case .navigate(let brief, _): navigate(brief)
        case .sendToChat(let prompt): lastAction = "Ready to send: \(prompt)"
        case .openURL(let url): lastAction = "Open link: \(url.absoluteString)"
        case .hostCapability(let id): lastAction = "Host action: \(id)"
        }
    }
}
