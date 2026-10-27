import AuriUI
import AuriUIRenderer
import SwiftUI

struct DemoCatalogView: View {
    let title: String
    let samples: [DemoSample]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(samples) { sample in
                        NavigationLink {
                            DemoSampleLoader(sample: sample)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sample.title)
                                    Text(sample.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            } icon: {
                                Image(systemName: sample.symbol)
                            }
                        }
                        .accessibilityIdentifier("demo.sample.\(sample.id)")
                    }
                } footer: {
                    Text("All examples work offline. AuriUI renders the document; this app handles its actions.")
                }
            }
            .navigationTitle(title)
        }
    }
}

private struct DemoSampleLoader: View {
    let sample: DemoSample
    @State private var session: AuriUIScreenSession?
    @State private var failure: String?

    var body: some View {
        Group {
            if let session {
                DemoSurfaceView(session: session, inline: sample.id == "inline")
            } else if let failure {
                ContentUnavailableView("Sample unavailable", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView()
            }
        }
        .task {
            guard session == nil, failure == nil else { return }
            do {
                session = try sample.session()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// The complete integration boundary: the renderer emits actions and the app
/// decides how to navigate, open links, or mutate its own state.
struct DemoSurfaceView: View {
    let session: AuriUIScreenSession
    var inline = false
    @State private var lastAction = "No action yet"
    @State private var destination: DemoDestination?
    @State private var savedFavoriteCount = 0

    var body: some View {
        Group {
            if inline {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("A host-owned screen")
                            .font(.title2.bold())
                        Text("This text belongs to the app. The interactive document below uses AuriUIView.")
                            .foregroundStyle(.secondary)
                        Divider()
                        AuriUIView(session: session, onAction: handle)
                    }
                    .padding()
                }
                .navigationTitle("Inline document")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                AuriUIScreenView(session: session, onSurfaceAction: handle)
            }
        }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DemoActionStatus(message: lastAction)
            }
            .navigationDestination(item: $destination) { destination in
                DemoSurfaceView(session: AuriUIScreenSession(document: destination.document, services: DemoServices.make()))
            }
            .onDisappear { session.cancel() }
    }

    private func handle(_ action: AuriUISurfaceAction) {
        switch action {
        case .navigate(let brief, _):
            lastAction = "Navigate: \(brief)"
            destination = DemoDestination(brief: brief)
        case .sendToChat(let prompt):
            lastAction = "Submitted: \(prompt)"
        case .openURL(let url):
            // The demo records link handoffs so it stays offline. A production
            // host can use SwiftUI's openURL environment action here.
            lastAction = "Open link: \(url.absoluteString)"
        case .hostCapability(let id):
            guard id == "demo.save" else { return }
            savedFavoriteCount += 1
            lastAction = "Favorite saved (\(savedFavoriteCount))"
        }
    }
}

struct DemoActionStatus: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Host result").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .textSelection(.enabled)
                .accessibilityIdentifier("demo.action")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial)
    }
}

private struct DemoDestination: Identifiable, Hashable {
    let id = UUID()
    let brief: String

    var document: AuriUIDocument {
        AuriUIDocument(
            screen: .init(id: id.uuidString, title: "Host navigation", tint: "indigo"),
            sections: [
                .header(emoji: "🧭", title: "A new screen", subtitle: "Supplied by this app"),
                .intro(text: brief),
                .button(.init(label: "Send from this screen", action: .send(prompt: brief)))
            ]
        )
    }
}
