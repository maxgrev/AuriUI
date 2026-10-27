import AuriUIRenderer
import Foundation
import Observation
import SwiftUI

enum DemoStreamScenario: String, CaseIterable, Identifiable {
    case success, truncated, failure, slow
    var id: Self { self }

    var title: String {
        switch self {
        case .success: "Complete stream"
        case .truncated: "Truncated stream"
        case .failure: "Failed stream"
        case .slow: "Cancel a stream"
        }
    }

    var detail: String {
        switch self {
        case .success: "Watch sections arrive, then use the finished screen."
        case .truncated: "Partial content stays visible. Retry to finish it."
        case .failure: "Show a provider error, then recover on retry."
        case .slow: "Cancel the producer while it waits for more output."
        }
    }
}

struct DemoStreamingView: View {
    var body: some View {
        NavigationStack {
            List(DemoStreamScenario.allCases) { scenario in
                NavigationLink {
                    DemoStreamScreen(scenario: scenario)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.title)
                        Text(scenario.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("demo.stream.\(scenario.rawValue)")
            }
            .navigationTitle("Streaming")
        }
    }
}

private struct DemoStreamScreen: View {
    @State private var provider: DemoStreamProvider
    @State private var session: AuriUIScreenSession
    @State private var wasCancelled = false
    @State private var lastAction = "No action yet"

    init(scenario: DemoStreamScenario) {
        let provider = DemoStreamProvider(scenario: scenario)
        _provider = State(initialValue: provider)
        _session = State(initialValue: AuriUIScreenSession(
            brief: "Show a small offline demonstration",
            grounded: false,
            services: AuriUIHostServices(stream: { request in provider.stream(request) })
        ))
    }

    var body: some View {
        AuriUIScreenView(session: session, onSurfaceAction: { action in
            if case .sendToChat(let prompt) = action {
                lastAction = "Submitted: \(prompt)"
            }
        })
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text(status)
                    .font(.caption.weight(.medium))
                    .accessibilityIdentifier("demo.stream.status")
                Spacer()
                if wasCancelled {
                    Button("Restart") {
                        wasCancelled = false
                        session.retry()
                    }
                    .accessibilityIdentifier("demo.stream.restart")
                } else if session.phase == .composing {
                    Button("Cancel") {
                        session.cancel()
                        wasCancelled = true
                    }
                    .accessibilityIdentifier("demo.stream.cancel")
                }
            }
            .padding(12)
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DemoActionStatus(message: lastAction)
        }
        .onDisappear { session.cancel() }
    }

    private var status: String {
        if wasCancelled {
            return provider.cancelledCount > 0 ? "Cancelled · producer stopped" : "Cancelling…"
        }
        switch session.phase {
        case .composing: return "Receiving sections…"
        case .ready: return "Complete · attempt \(provider.attempts)"
        case .failed: return "Needs retry · attempt \(provider.attempts)"
        }
    }
}

/// An injected provider with the same contract as a network or model client.
/// It emits real incremental deltas and requires a final document event.
@MainActor
@Observable
final class DemoStreamProvider {
    let scenario: DemoStreamScenario
    private(set) var attempts = 0
    private(set) var cancelledCount = 0

    init(scenario: DemoStreamScenario) {
        self.scenario = scenario
    }

    func stream(_ request: AuriUIStreamRequest) -> AsyncThrowingStream<AuriUIStreamEvent, Error> {
        attempts += 1
        let shouldFail = attempts == 1 && scenario == .failure
        let shouldTruncate = attempts == 1 && scenario == .truncated
        let shouldWait = attempts == 1 && scenario == .slow

        return AsyncThrowingStream { continuation in
            let producer = Task { @MainActor [weak self] in
                do {
                    continuation.yield(.designing)
                    try await Task.sleep(for: .milliseconds(250))
                    if shouldFail {
                        throw DemoStreamError.unavailable
                    }

                    let text = try DemoResources.text("stream")
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                    for (index, line) in lines.enumerated() {
                        try Task.checkCancellation()
                        continuation.yield(.delta(String(line) + "\n"))
                        if index == 3 && shouldTruncate {
                            continuation.finish()
                            return
                        }
                        if index == 3 && shouldWait {
                            try await Task.sleep(for: .seconds(30))
                        }
                        try await Task.sleep(for: .milliseconds(120))
                    }
                    continuation.yield(.document(text: text, screenID: "offline-demo"))
                    continuation.finish()
                } catch is CancellationError {
                    self?.cancelledCount += 1
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

private enum DemoStreamError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The demo provider is unavailable. Try again to recover."
    }
}
