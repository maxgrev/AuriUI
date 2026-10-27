#if os(iOS) || os(macOS)
import AuriUI
import AuriUIRenderer
import Foundation
import Testing

@MainActor
@Suite("Public renderer sessions", .enabled(if: supportsRendererSessions))
struct SessionTests {
    @Test("An authoritative document replaces its prefix and completes exactly once")
    func authoritativeCompletion() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        var snapshots: [AuriUISurfaceSnapshot] = []
        let session = AuriUIScreenSession(brief: "Lunch", services: provider.services) { session in
            if let snapshot = session.persistenceSnapshot { snapshots.append(snapshot) }
        }
        defer { session.cancel(); provider.finishAll() }
        session.start()
        session.start()
        try await eventually { provider.requests.count == 1 }
        #expect(provider.requests[0] == AuriUIStreamRequest(brief: "Lunch", grounded: true))

        provider.yield(.delta("aui 1\nintro \"Draft\"\n"))
        try await eventually { session.document.isRenderable }
        #expect(session.phase == .composing)
        #expect(session.persistenceSnapshot == nil)

        provider.yield(.document(text: Self.completeText, screenID: "server-id"))
        // An accidental trailing provider event must not replace committed content.
        provider.yield(.delta("intro \"Unexpected trailing text\"\n"))
        provider.finish()
        try await eventually { session.phase == .ready }
        #expect(session.document == AuriUIStreamingParser.parse(Self.completeText))
        #expect(session.sourceText == Self.completeText)
        #expect(snapshots.map(\.auiText) == [Self.completeText])
        #expect(provider.completionEvents.count == 1)
        #expect(provider.failureEvents.isEmpty)
    }

    @Test("Truncated and failed streams keep readable content without saving it", arguments: [false, true])
    func incompleteStream(throwsError: Bool) async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        var readyCount = 0
        let session = AuriUIScreenSession(brief: "Partial", services: provider.services) { _ in
            readyCount += 1
        }
        defer { session.cancel(); provider.finishAll() }
        session.start()
        try await eventually { provider.requests.count == 1 }
        provider.yield(.delta("aui 1\nintro \"Readable partial result\""))
        provider.finish(throwing: throwsError ? ProviderFailure.disconnected : nil)
        try await eventually { session.hasFailed }

        #expect(session.document.sections == [.intro(text: "Readable partial result")])
        #expect(session.sourceText == nil)
        #expect(session.persistenceSnapshot == nil)
        #expect(readyCount == 0)
        #expect(provider.completionEvents.isEmpty)
        #expect(provider.failureEvents.count == 1)
    }

    @Test("Selection and form edits survive streamed and authoritative reparsing")
    func interactionReplay() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        let session = AuriUIScreenSession(brief: "Customize", services: provider.services)
        defer { session.cancel(); provider.finishAll() }
        session.start()
        try await eventually { provider.requests.count == 1 }
        provider.yield(.delta(Self.interactiveText + "\n"))
        try await eventually { session.formStates["preferences"] != nil }

        #expect(session.firstInvalidFieldID(in: "preferences") == "note")
        session.select(group: "size", value: "large")
        session.toggle(value: "cheese")
        session[formID: "preferences", fieldID: "note"] = "Keep {selections} literal"
        #expect(session.isFormValid("preferences"))

        provider.yield(.delta("intro \"More content\"\n"))
        try await eventually { session.document.sections.last == .intro(text: "More content") }
        #expect(session.selection.total == Decimal(string: "13.25"))
        #expect(session.selection.selectionSummary == "Large, Cheese")
        #expect(session[formID: "preferences", fieldID: "note"] == "Keep {selections} literal")

        provider.yield(.document(text: Self.interactiveText + "\nintro \"Final\"", screenID: nil))
        try await eventually { session.phase == .ready }
        #expect(session.selection.total == Decimal(string: "13.25"))
        #expect(session.formReviewSummary("preferences") == "Note: Keep {selections} literal")
        #expect(session.interpolated(.send(prompt: "{selections}: {note}"), formID: "preferences")
            == .send(prompt: "Large, Cheese: Keep {selections} literal"))
    }

    @Test("Resources and host lookup providers survive snapshot restoration")
    func resourcesAndRestoration() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        let firstURL = try #require(URL(string: "https://example.com/first"))
        let finalURL = try #require(URL(string: "https://example.com/final"))
        let lookupURL = try #require(URL(string: "https://example.com/search?q=coffee"))
        var services = provider.services
        services = AuriUIHostServices(
            stream: services.stream,
            lookupURL: { query in query == "coffee" ? lookupURL : nil }
        )
        let session = AuriUIScreenSession(brief: "Resources", services: services)
        defer { session.cancel(); provider.finishAll() }
        session.start()
        try await eventually { provider.requests.count == 1 }
        provider.yield(.resources(["R1": firstURL, "unsafe": URL(fileURLWithPath: "/tmp/private")]))
        provider.yield(.resources(["r1": finalURL]))
        provider.yield(.document(text: Self.completeText, screenID: nil))
        try await eventually { session.phase == .ready }

        #expect(session.resolveURL(.resource(id: "R1")) == finalURL)
        #expect(session.resolveURLString("find:coffee") == lookupURL)
        #expect(session.resolveURLString("r99") == nil)
        #expect(session.resources["unsafe"] == nil)
        let snapshot = try #require(session.persistenceSnapshot)
        let restored = try #require(AuriUIScreenSession(snapshot: snapshot, services: services))
        restored.start()
        #expect(restored.phase == .ready)
        #expect(restored.document == session.document)
        #expect(restored.resolveURL(.resource(id: "r1")) == finalURL)
        #expect(restored.resolveURL(.lookup(query: "coffee")) == lookupURL)
        #expect(provider.requests.count == 1)
        #expect(AuriUIScreenSession(snapshot: AuriUISurfaceSnapshot(
            brief: "Future", grounded: false, auiText: "aui 2\nintro \"Unsupported\""
        )) == nil)
    }

    @Test("Missing providers and invalid saved text expose errors")
    func missingProviderAndInvalidAnswer() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let session = AuriUIScreenSession(brief: "No provider")
        defer { session.cancel() }
        session.start()
        try await eventually { session.hasFailed }
        #expect(session.phase == .failed(AuriUICompositionError.missingProvider.localizedDescription))
        #expect(session.persistenceSnapshot == nil)

        let invalid = AuriUIScreenSession(answerText: "aui 2\nintro \"Do not render\"")
        #expect(invalid.hasFailed)
        #expect(!invalid.document.isRenderable)
        #expect(invalid.persistenceSnapshot == nil)
    }

    @Test("Retry replaces failed or canceled requests without accepting stale events", arguments: [false, true])
    func retryIgnoresStaleEvents(afterFailure: Bool) async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        var readyCount = 0
        let session = AuriUIScreenSession(brief: "Retry", services: provider.services) { _ in readyCount += 1 }
        defer { session.cancel(); provider.finishAll() }
        session.start()
        try await eventually { provider.requests.count == 1 }
        provider.yield(.delta("aui 1\nintro \"Old prefix\"\n"))
        try await eventually { session.document.isRenderable }

        if afterFailure {
            provider.finish(throwing: ProviderFailure.disconnected)
            try await eventually { session.hasFailed }
        }

        // Both calls run on the main actor before the old task can read this event.
        provider.yield(.document(text: "aui 1\nintro \"Stale completion\"", screenID: nil), request: 0)
        session.retry()
        #expect(!session.document.isRenderable)
        #expect(session.sourceText == nil)
        try await eventually { provider.requests.count == 2 }
        provider.finish(request: 0)
        provider.yield(.document(text: Self.completeText, screenID: nil), request: 1)
        provider.finish(request: 1)
        try await eventually { session.phase == .ready }

        #expect(session.document == AuriUIStreamingParser.parse(Self.completeText))
        #expect(readyCount == 1)
        #expect(provider.completionEvents.count == 1)
        #expect(provider.failureEvents.count == (afterFailure ? 1 : 0))
    }

    @Test("Cancellation publishes no failure and restart discards partial resources")
    func cancellationAndRestart() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        let session = AuriUIScreenSession(brief: "Cancel", services: provider.services)
        defer { session.cancel(); provider.finishAll() }
        session.start()
        try await eventually { provider.requests.count == 1 }
        let partialURL = try #require(URL(string: "https://example.com/partial"))
        provider.yield(.resources(["r1": partialURL]))
        provider.yield(.delta("aui 1\nintro \"Canceled prefix\"\n"))
        try await eventually { session.document.isRenderable }

        session.cancel()
        #expect(session.phase == .composing)
        #expect(session.persistenceSnapshot == nil)
        session.start()
        #expect(session.document == AuriUIDocument())
        #expect(session.resources.isEmpty)
        try await eventually { provider.requests.count == 2 }
        provider.yield(.document(text: Self.completeText, screenID: nil), request: 1)
        try await eventually { session.phase == .ready }
        #expect(session.resources.isEmpty)
        #expect(provider.failureEvents.isEmpty)
    }

    @Test("Capabilities stay local to each host and preserve the host-only boundary")
    func capabilityIsolation() {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let allowed = AuriUIScreenSession(document: AuriUIDocument(), services: .init(capabilities: [.send]))
        let denied = AuriUIScreenSession(document: AuriUIDocument(), services: .init(capabilities: []))
        #expect(allowed.canPerform(.send(prompt: "Hello")))
        #expect(allowed.canSubmitForm(to: "send"))
        #expect(!denied.canPerform(.send(prompt: "Hello")))
        #expect(!denied.canSubmitForm(to: "send"))
        #expect(!allowed.canPerform(.nav(brief: "Next")))

        let localAction = AuriUIAction.hostCapability(id: "reset")
        let trustedDocument = AuriUIDocument(sections: [
            .button(AuriUIButton(label: "Reset", action: localAction)),
        ])
        let trusted = AuriUIScreenSession(document: trustedDocument, services: .init(capabilities: [
            AuriUICapability(id: "reset", description: "Reset local state", acceptsFormInput: true, exposure: .hostOnly),
            AuriUICapability(id: "send", description: "Unavailable", acceptsFormInput: true, isAvailable: { false }),
        ]))
        #expect(trusted.canPerform(localAction))
        #expect(!allowed.canPerform(localAction))
        #expect(!trusted.canSubmitForm(to: "reset"))
        #expect(!trusted.canPerform(.send(prompt: "Hello")))
        #expect(!trusted.canSubmitForm(to: "send"))

        let generated = AuriUIStreamingParser.parse("button \"Reset\" @hostCapability(\"reset\")")
        guard case .button(let parsedButton)? = generated.sections.first else {
            Issue.record("Expected a button with its unknown action removed")
            return
        }
        #expect(parsedButton.action == nil)
        let composerOnly = AuriUIHostServices(capabilities: [AuriUICapability(id: "reset", description: "Composer")])
        #expect(!composerOnly.canPerform(localAction))
    }

    @Test("URL actions require both an enabled capability and a resolvable target")
    func urlActionability() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let target = try #require(URL(string: "https://example.com/coffee"))
        let unresolved = AuriUIScreenSession(answerText: Self.completeText)
        #expect(!unresolved.canPerform(.url(.lookup(query: "coffee"))))
        #expect(!unresolved.canPerform(.url(.resource(id: "r1"))))
        #expect(unresolved.canPerform(.url(.direct(target))))

        let resources = #"{"R1":"https://example.com/coffee"}"#
        let resolved = AuriUIScreenSession(
            answerText: Self.completeText,
            resourcesJSON: resources,
            services: AuriUIHostServices(
                capabilities: [.url],
                lookupURL: { query in query == "coffee" ? target : nil }
            )
        )
        #expect(resolved.canPerform(.url(.resource(id: "r1"))))
        #expect(resolved.canPerform(.url(.lookup(query: "coffee"))))
        #expect(!resolved.canPerform(.url(.resource(id: "r2"))))
        #expect(!resolved.canPerform(.url(.lookup(query: "unknown"))))

        let disabled = AuriUIScreenSession(
            answerText: Self.completeText,
            resourcesJSON: resources,
            services: AuriUIHostServices(capabilities: [], lookupURL: { _ in target })
        )
        #expect(!disabled.canPerform(.url(.resource(id: "r1"))))
        #expect(!disabled.canPerform(.url(.lookup(query: "coffee"))))
        #expect(!disabled.canPerform(.url(.direct(target))))
    }

    @Test("Markdown, direct, resource, and lookup links share the web URL policy", arguments: [
        "file:///tmp/private", "javascript:alert(1)", "custom-app://action",
        "mailto:person@example.com", "tel:+15551234567", "https:missing-host",
        "https://name:secret@example.com/private",
    ])
    func unsafeURLActions(text: String) throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let url = try #require(URL(string: text))
        let resources = String(decoding: try JSONEncoder().encode(["r1": text]), as: UTF8.self)
        let session = AuriUIScreenSession(
            answerText: "aui 1\nintro \"[Open](\(text))\"",
            resourcesJSON: resources,
            services: AuriUIHostServices(lookupURL: { _ in url })
        )
        // Markdown link taps enter through this same direct-action boundary.
        for target in [AuriUIURLTarget.direct(url), .resource(id: "r1"), .lookup(query: "link")] {
            #expect(session.resolveURL(target) == nil)
            #expect(!session.canPerform(.url(target)))
        }
    }

    @Test("Session stores reuse interaction state and save only completed snapshots")
    func storeReuseAndSnapshots() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        var saved: [AuriUISurfaceSnapshot] = []
        let store = AuriUISurfaceSessionStore(services: provider.services) { saved.append($0) }
        let session = store.session(parentID: "parent", brief: "Lunch choices", grounded: false)
        let same = store.session(parentID: "parent", brief: "  LUNCH  choices\n", grounded: false)
        let otherParent = store.session(parentID: "other", brief: "Lunch choices", grounded: false)
        #expect(session === same)
        #expect(session !== otherParent)
        defer { session.cancel(); otherParent.cancel(); provider.finishAll(); store.cancelPendingPrefetches() }

        session.start()
        try await eventually { provider.requests.count == 1 }
        provider.yield(.delta(Self.interactiveText + "\n"))
        try await eventually { session.document.isRenderable }
        #expect(saved.isEmpty)
        provider.yield(.document(text: Self.interactiveText, screenID: nil))
        try await eventually { session.phase == .ready }
        session.toggle(value: "cheese")
        #expect(store.session(parentID: "parent", brief: "Lunch choices", grounded: false).selection.isToggled(value: "cheese"))
        store.discardIfComposing(session, parentID: "parent", brief: "Lunch choices", grounded: false)
        #expect(store.session(parentID: "parent", brief: "Lunch choices", grounded: false) === session)
        #expect(saved.count == 1)

        let restoredStore = AuriUISurfaceSessionStore(
            archive: AuriUISurfaceSnapshotArchive(snapshots: saved), services: provider.services
        )
        let restored = restoredStore.session(parentID: "parent", brief: "Lunch choices", grounded: false)
        restored.start()
        #expect(restored.phase == .ready)
        #expect(restored.document == session.document)
        #expect(provider.requests.count == 1)
    }

    @Test("Discarding a canceled partial session starts with a new parser")
    func storeDiscard() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        let store = AuriUISurfaceSessionStore(services: provider.services)
        let first = store.session(parentID: nil, brief: "Draft", grounded: true)
        first.start()
        try await eventually { provider.requests.count == 1 }
        provider.yield(.delta("aui 1\nintro \"Partial\"\n"))
        try await eventually { first.document.isRenderable }
        let unrelated = AuriUIScreenSession(brief: "Unrelated")
        store.discardIfComposing(unrelated, parentID: nil, brief: "Draft", grounded: true)
        #expect(store.session(parentID: nil, brief: "Draft", grounded: true) === first)

        store.discardIfComposing(first, parentID: nil, brief: "Draft", grounded: true)
        let replacement = store.session(parentID: nil, brief: "Draft", grounded: true)
        defer { first.cancel(); replacement.cancel(); provider.finishAll() }
        #expect(replacement !== first)
        #expect(!replacement.document.isRenderable)
        replacement.start()
        try await eventually { provider.requests.count == 2 }
        provider.yield(.document(text: Self.completeText, screenID: nil), request: 1)
        try await eventually { replacement.phase == .ready }
        #expect(replacement.document == AuriUIStreamingParser.parse(Self.completeText))
    }

    @Test("Prefetch is opt-in and cache hits stay within a parent and provider")
    func prefetchIsolation() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let provider = ControlledProvider()
        let disabled = AuriUIScreenPrefetcher(services: provider.services)
        disabled.prefetch(briefs: ["Next"], parentID: "parent")
        #expect(provider.requests.isEmpty)

        var services = provider.services
        services.prefetchEnabled = true
        let prefetcher = AuriUIScreenPrefetcher(services: services)
        let separate = AuriUIScreenPrefetcher(services: services)
        defer { prefetcher.cancelPending(); separate.cancelPending(); provider.finishAll() }
        prefetcher.prefetch(briefs: ["Next", " next ", "With {selections}"], parentID: "parent")
        try await eventually { provider.requests.count == 1 }
        #expect(provider.requests[0] == AuriUIStreamRequest(brief: "Next", grounded: false))
        provider.yield(.document(text: Self.completeText, screenID: nil))
        try await eventually { prefetcher.cachedSnapshot(for: "Next", grounded: false, parentID: "parent") != nil }
        #expect(prefetcher.cachedSnapshot(for: "Next", grounded: false, parentID: "other") == nil)
        #expect(prefetcher.cachedSnapshot(for: "Next", grounded: true, parentID: "parent") == nil)
        #expect(separate.cachedSnapshot(for: "Next", grounded: false, parentID: "parent") == nil)

        let cached = AuriUIScreenSession(
            brief: " next ", grounded: false, parentID: "parent", prefetcher: prefetcher, services: services
        )
        cached.start()
        #expect(cached.phase == .ready)
        #expect(cached.document == AuriUIStreamingParser.parse(Self.completeText))
        #expect(provider.requests.count == 1)
        #expect(provider.completionEvents.contains { event in
            if case .composed(_, let hit, _) = event { return hit }
            return false
        })
    }

    private static let completeText = """
    aui 1
    screen complete "Complete"
    intro "Authoritative result"
    """

    private static let interactiveText = """
    aui 1
    state base:10 cur:USD
    list "Size" pick:size
    item "Small" val:small price:0 sel
    item "Large" val:large price:2
    list "Extras" multi
    item "Cheese" val:cheese price:1.25
    form preferences "Preferences" cap:send
    field text note "Note" required
    submit "Continue" @send("{selections}: {note}")
    """
}

private var supportsRendererSessions: Bool {
    if #available(iOS 17.0, macOS 14.0, *) { return true }
    return false
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
private final class ControlledProvider {
    private(set) var requests: [AuriUIStreamRequest] = []
    private(set) var telemetry: [AuriUITelemetryEvent] = []
    private var continuations: [AsyncThrowingStream<AuriUIStreamEvent, Error>.Continuation] = []

    var services: AuriUIHostServices {
        AuriUIHostServices(
            stream: { [self] request in
                let (stream, continuation) = AsyncThrowingStream<AuriUIStreamEvent, Error>.makeStream()
                requests.append(request)
                continuations.append(continuation)
                return stream
            },
            onTelemetry: { [self] event in telemetry.append(event) }
        )
    }

    var completionEvents: [AuriUITelemetryEvent] {
        telemetry.filter { if case .composed = $0 { return true }; return false }
    }

    var failureEvents: [AuriUITelemetryEvent] {
        telemetry.filter { if case .failed = $0 { return true }; return false }
    }

    func yield(_ event: AuriUIStreamEvent, request: Int = 0) {
        continuations[request].yield(event)
    }

    func finish(request: Int = 0, throwing error: Error? = nil) {
        continuations[request].finish(throwing: error)
    }

    func finishAll() {
        continuations.forEach { $0.finish() }
    }
}

private enum ProviderFailure: Error {
    case disconnected
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
private extension AuriUIScreenSession {
    var hasFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
private func eventually(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    for _ in 0..<200 {
        if condition() { return }
        await Task.yield()
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "Timed out waiting for the controlled stream", sourceLocation: sourceLocation)
}
#endif
