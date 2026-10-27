#if os(iOS) || os(macOS)
//
//  AuriUIScreenSession.swift
//  Auri
//
//  Drives one generated surface (Visual Engine v2): streams AuriUI text from
//  the /screen speed lane into the streaming parser, keeps the document
//  snapshot the renderer draws, and owns selection state. User selections are
//  replayed onto every re-parse, so tapping during streaming is safe.
//

import AuriUI
import Foundation
import Observation

/// A detail page wrapped for sheet presentation.
@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIPresentedPage: Identifiable {
    public var id: String { page.forTitle }
    public let page: AuriUIPage
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class AuriUIScreenSession {

    public enum Phase: Equatable {
        case composing
        case ready
        case failed(String)
    }

    /// Stable identity for view-scoped persistence (e.g. step checkmarks).
    public let id: String
    public let brief: String
    public let services: AuriUIHostServices
    /// Roots ground (planner + search); children inherit facts via @nav
    /// briefs and skip the hop for speed.
    public let grounded: Bool
    /// The screen whose action opened this one. Speculative cache hits must
    /// match this parent as well as the brief.
    private let parentID: String?
    private let prefetcher: AuriUIScreenPrefetcher?

    public private(set) var phase: Phase = .composing
    public private(set) var document = AuriUIDocument()
    public private(set) var selection: AuriUISelectionState
    public private(set) var formStates: [String: AuriUIFormState] = [:]
    /// Grounded link targets (r-id → real URL) from the DATA block.
    public private(set) var resources: [String: URL] = [:]
    /// Authoritative AuriUI source retained so a ready screen can be restored
    /// through the same parser after the app or conversation is reopened.
    public private(set) var sourceText: String?
    /// The tap-to-open detail page currently presented as a sheet.
    public var presentedPage: AuriUIPresentedPage?

    private var parser = AuriUIStreamingParser()
    /// User intent, replayed onto each fresh parse in tap order.
    private var pickActions: [(group: String, value: String)] = []
    private var toggleFlips: [String] = []
    private var formEdits: [String: [String: String]] = [:]
    @ObservationIgnored private var pageSessions: [String: AuriUIScreenSession] = [:]
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    private var streamGeneration = 0
    private var hasStarted = false
    private var reportedReady = false
    private var composeStartedAt = Date()
    private var onReady: ((AuriUIScreenSession) -> Void)?

    public init(
        brief: String,
        grounded: Bool = true,
        parentID: String? = nil,
        id: String = UUID().uuidString,
        prefetcher: AuriUIScreenPrefetcher? = nil,
        services: AuriUIHostServices = AuriUIHostServices(),
        onReady: ((AuriUIScreenSession) -> Void)? = nil
    ) {
        self.id = id
        self.services = services
        self.brief = brief
        self.grounded = grounded
        self.parentID = parentID
        self.prefetcher = prefetcher
        self.selection = AuriUISelectionState(document: AuriUIDocument())
        self.onReady = onReady
    }

    /// Rehydrates a completed generated screen without touching the network.
    public init?(
        snapshot: AuriUISurfaceSnapshot,
        parentID: String? = nil,
        id: String = UUID().uuidString,
        prefetcher: AuriUIScreenPrefetcher? = nil,
        services: AuriUIHostServices = AuriUIHostServices()
    ) {
        guard snapshot.isCompatible else { return nil }
        let parsed = AuriUIStreamingParser.parse(snapshot.auiText)
        guard parsed.isRenderable else { return nil }

        self.id = id
        self.services = services
        self.brief = snapshot.brief
        self.grounded = snapshot.grounded
        self.parentID = parentID
        self.prefetcher = prefetcher
        self.sourceText = snapshot.auiText
        self.document = parsed
        self.selection = AuriUISelectionState(document: parsed)
        self.formStates = Self.initialFormStates(for: parsed)
        self.resources = Self.resolveResources(snapshot.resources)
        self.phase = .ready
        self.hasStarted = true
        self.reportedReady = true
    }

    /// A ready session for an already-composed document (persisted chat
    /// answers): no streaming, no telemetry — parse, resolve, render.
    public init(answerText: String, resourcesJSON: String? = nil, id: String = UUID().uuidString, services: AuriUIHostServices = AuriUIHostServices()) {
        self.id = id
        self.services = services
        self.brief = ""
        self.grounded = false
        self.parentID = nil
        self.prefetcher = nil
        var parser = AuriUIStreamingParser()
        parser.consume(answerText)
        parser.finish()
        let parsed = parser.document
        self.document = parsed
        self.selection = AuriUISelectionState(document: parsed)
        self.formStates = Self.initialFormStates(for: parsed)
        self.phase = parser.failure.map { .failed($0.localizedDescription) } ?? .ready
        self.hasStarted = true
        self.reportedReady = true
        self.sourceText = answerText

        if let resourcesJSON,
           let data = resourcesJSON.data(using: .utf8),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            self.resources = Self.resolveResources(map)
        }
    }

    /// A ready session for a trusted document built by the containing app.
    /// Host-only actions enter AuriUI through this initializer, never through
    /// the model-facing parser.
    public init(document: AuriUIDocument, id: String = UUID().uuidString, services: AuriUIHostServices = AuriUIHostServices()) {
        self.id = id
        self.services = services
        self.brief = ""
        self.grounded = false
        self.parentID = nil
        self.prefetcher = nil
        self.document = document
        self.selection = AuriUISelectionState(document: document)
        self.formStates = Self.initialFormStates(for: document)
        self.phase = .ready
        self.hasStarted = true
        self.reportedReady = true
    }

    public func replaceTrustedDocument(_ document: AuriUIDocument) {
        self.document = document
        selection = AuriUISelectionState(document: document)
        formStates = Self.initialFormStates(for: document)
        presentedPage = nil
        pageSessions.removeAll()
    }

    public var title: String? { document.screen?.title }
    public var subtitle: String? { document.screen?.subtitle }

    // MARK: - Streaming

    /// Idempotent; call from the screen's `.task`.
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        composeStartedAt = Date()

        // A speculated screen skips the network entirely — the 0 ms tap.
        if let parentID,
           let cached = prefetcher?.cachedSnapshot(
            for: brief,
            grounded: grounded,
            parentID: parentID
        ) {
            document = AuriUIStreamingParser.parse(cached.auiText)
            sourceText = cached.auiText
            resources = Self.resolveResources(cached.resources)
            rebuildInteractionState()
            phase = .ready
            didBecomeReady(cacheHit: true)
            return
        }

        streamGeneration += 1
        let generation = streamGeneration
        parser = AuriUIStreamingParser()
        document = AuriUIDocument()
        resources = [:]
        sourceText = nil
        rebuildInteractionState()
        phase = .composing
        streamTask = Task { [weak self] in
            await self?.run(generation: generation)
        }
    }

    public func cancel() {
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        if phase == .composing { hasStarted = false }
    }

    deinit {
        streamTask?.cancel()
    }

    public func retry() {
        cancel()
        hasStarted = false
        reportedReady = false
        parser = AuriUIStreamingParser()
        document = AuriUIDocument()
        sourceText = nil
        resources = [:]
        rebuildInteractionState()
        phase = .composing
        start()
    }

    private func run(generation: Int) async {
        do {
            guard let stream = services.stream else { throw AuriUICompositionError.missingProvider }
            for try await event in stream(AuriUIStreamRequest(brief: brief, grounded: grounded)) {
                try Task.checkCancellation()
                guard generation == streamGeneration else { return }
                switch event {
                case .designing:
                    break
                case .resources(let map):
                    resources.merge(Self.resolveResources(map.mapValues(\.absoluteString))) { _, new in new }
                    refreshPageSessions()
                case .delta(let text):
                    let changed = parser.consume(text)
                    if let failure = parser.failure { throw failure }
                    if changed {
                        document = parser.document
                        rebuildInteractionState()
                    }
                case .document(let text, _):
                    // The server-validated text is authoritative; a fresh
                    // parse also runs page reconciliation.
                    var completeParser = AuriUIStreamingParser()
                    completeParser.consume(text)
                    completeParser.finish()
                    if let failure = completeParser.failure { throw failure }
                    let parsed = completeParser.document
                    guard parsed.isRenderable else { throw AuriUICompositionError.emptyResult }
                    sourceText = text
                    document = parsed
                    rebuildInteractionState()
                    phase = .ready
                    didBecomeReady(cacheHit: false)
                    return
                }
            }
            try Task.checkCancellation()
            guard generation == streamGeneration else { return }
            failFromParser()
        } catch is CancellationError {
            // Screen was popped; nothing to report.
        } catch {
            guard generation == streamGeneration, !Task.isCancelled else { return }
            failFromParser(message: error.localizedDescription)
        }
    }

    /// A readable prefix remains useful context, but it is never authoritative:
    /// only `aui.document` may make a screen ready or eligible for persistence.
    private func failFromParser(message: String? = nil) {
        guard phase == .composing else { return }
        parser.finish()
        if parser.document.isRenderable {
            document = parser.document
            rebuildInteractionState()
        }
        phase = .failed(message ?? String(localized: "This screen couldn't be generated."))
        services.onTelemetry(.failed(
            latencyMilliseconds: Int(Date().timeIntervalSince(composeStartedAt) * 1000),
            partialSectionCount: document.sections.count
        ))
    }

    /// Once per screen: score the compose (the Sushi Test's telemetry) and
    /// hand every reachable @nav brief to the speculation engine so the next
    /// tap lands instantly.
    private func didBecomeReady(cacheHit: Bool) {
        guard !reportedReady else { return }
        reportedReady = true
        services.onTelemetry(.composed(
            latencyMilliseconds: Int(Date().timeIntervalSince(composeStartedAt) * 1000),
            cacheHit: cacheHit,
            sectionCount: document.sections.count
        ))
        prefetcher?.prefetch(briefs: document.navBriefs, parentID: id)

        if let onReady, persistenceSnapshot != nil {
            self.onReady = nil
            onReady(self)
        }
    }

    /// Re-activates this screen's candidates when navigating back to an
    /// already-ready session.
    public func becameVisible() {
        guard phase == .ready else { return }
        prefetcher?.prefetch(briefs: document.navBriefs, parentID: id)
    }

    public var persistenceSnapshot: AuriUISurfaceSnapshot? {
        guard phase == .ready, let sourceText, document.isRenderable else {
            return nil
        }
        return AuriUISurfaceSnapshot(
            brief: brief,
            grounded: grounded,
            auiText: sourceText,
            resources: resources.mapValues(\.absoluteString)
        )
    }

    // MARK: - Selection

    public func select(group: String, value: String) {
        pickActions.append((group: group, value: value))
        selection.select(group: group, value: value)
    }

    public func toggle(value: String) {
        toggleFlips.append(value)
        selection.toggle(value: value)
    }

    public func interpolate(_ string: String) -> String {
        selection.interpolate(string, locale: Locale.current)
    }

    public func interpolated(_ action: AuriUIAction) -> AuriUIAction {
        selection.interpolated(action, locale: Locale.current)
    }

    // MARK: - Forms

    public subscript(formID formID: String, fieldID fieldID: String) -> String {
        get { formStates[formID]?[fieldID] ?? "" }
        set {
            guard var state = formStates[formID],
                  state.form.fields.contains(where: { $0.id == fieldID }) else { return }
            state[fieldID] = newValue
            formEdits[formID, default: [:]][fieldID] = state[fieldID]
            formStates[formID] = state
        }
    }

    public func formValidationIssue(
        formID: String,
        fieldID: String
    ) -> AuriUIFormValidationIssue? {
        formStates[formID]?.validationIssue(for: fieldID)
    }

    public func isFormValid(_ formID: String) -> Bool {
        formStates[formID]?.isValid ?? false
    }

    public func firstInvalidFieldID(in formID: String) -> String? {
        formStates[formID]?.firstInvalidFieldID
    }

    public func formReviewSummary(_ formID: String) -> String {
        formStates[formID]?.reviewSummary ?? ""
    }

    /// Selection placeholders are resolved on the authored template first;
    /// form values are inserted last, so user-entered braces stay literal.
    public func interpolated(_ action: AuriUIAction, formID: String) -> AuriUIAction {
        let selectionAction = selection.interpolated(action, locale: Locale.current)
        return formStates[formID]?.interpolated(selectionAction) ?? selectionAction
    }

    // MARK: - Detail pages

    public func page(for title: String) -> AuriUIPage? {
        document.pages.first { $0.forTitle == title }
    }

    /// Detail pages own their controls and totals. Reopening a page reuses
    /// its live state without mixing identically named options on other pages.
    public func pageSession(for page: AuriUIPage) -> AuriUIScreenSession {
        let current = self.page(for: page.forTitle) ?? page
        if let cached = pageSessions[current.forTitle] { return cached }
        let child = AuriUIScreenSession(
            document: pageDocument(current),
            id: "\(id).page.\(current.forTitle)",
            services: services
        )
        child.resources = resources
        pageSessions[current.forTitle] = child
        return child
    }

    private func pageDocument(_ page: AuriUIPage) -> AuriUIDocument {
        AuriUIDocument(
            screen: document.screen,
            money: page.money ?? document.money,
            sections: page.sections,
            pages: document.pages
        )
    }

    private func refreshPageSessions() {
        for (title, child) in pageSessions {
            guard let page = page(for: title) else {
                pageSessions.removeValue(forKey: title)
                continue
            }
            child.document = pageDocument(page)
            child.resources = resources
            child.rebuildInteractionState()
        }
    }

    public func presentPage(titled title: String) {
        guard let page = page(for: title) else { return }
        presentedPage = AuriUIPresentedPage(page: page)
    }

    public func dismissPresentedPage() {
        presentedPage = nil
    }

    public func canPerform(_ action: AuriUIAction) -> Bool {
        guard services.canPerform(action) else { return false }
        if case .url(let target) = action {
            return resolveURL(target) != nil
        }
        return true
    }

    public func canSubmitForm(to capabilityID: String) -> Bool {
        services.canSubmitForm(to: capabilityID)
    }

    // MARK: - URL resolution

    /// The model cites references; only real URLs leave this method.
    public func resolveURL(_ target: AuriUIURLTarget) -> URL? {
        let url: URL? = switch target {
        case .direct(let url): url
        case .resource(let id): resources[id.lowercased()]
        case .lookup(let query): services.lookupURL(query: query)
        }
        return url.flatMap(Self.validatedWebURL)
    }

    /// Resolves a `url:` string field (`sources` items): r-id, find:, or
    /// literal. Unresolvable references yield nil and the element drops.
    public func resolveURLString(_ string: String) -> URL? {
        AuriUIURLTarget(parsing: string).flatMap(resolveURL)
    }

    private func rebuildInteractionState() {
        var state = AuriUISelectionState(document: document)
        for action in pickActions {
            state.select(group: action.group, value: action.value)
        }
        for value in toggleFlips {
            state.toggle(value: value)
        }
        selection = state

        var rebuiltForms = Self.initialFormStates(for: document)
        for (formID, edits) in formEdits {
            guard var formState = rebuiltForms[formID] else { continue }
            for (fieldID, value) in edits {
                formState[fieldID] = value
            }
            rebuiltForms[formID] = formState
        }
        formStates = rebuiltForms
        refreshPageSessions()
    }

    private static func initialFormStates(
        for document: AuriUIDocument
    ) -> [String: AuriUIFormState] {
        // Detail pages have separate sessions, so only this surface's forms
        // (including its tabs) participate in its interaction state.
        AuriUIDocument(sections: document.sections).forms.reduce(into: [:]) { states, form in
            if states[form.id] == nil { states[form.id] = AuriUIFormState(form: form) }
        }
    }

    private static func resolveResources(_ resources: [String: String]) -> [String: URL] {
        resources.reduce(into: [:]) { resolved, entry in
            guard let url = URL(string: entry.value),
                  let url = validatedWebURL(url) else {
                return
            }
            resolved[entry.key.lowercased()] = url
        }
    }

    private static func validatedWebURL(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.user == nil, components.password == nil else { return nil }
        return url
    }
}

/// Answer-scoped ownership for generated child surfaces.
///
/// Presentation is intentionally ephemeral (a sheet can be dismissed and
/// recreated), while the generated screen is part of the answer the user is
/// exploring. Keeping sessions here makes the resolved brief the identity of
/// that screen, so content, selections, resources, and embedded page state do
/// not regenerate with each presentation.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class AuriUISurfaceSessionStore {

    private struct Key: Hashable {
        let parentID: String?
        let brief: String
        let grounded: Bool

        init(parentID: String?, brief: String, grounded: Bool) {
            self.parentID = parentID
            self.brief = AuriUISurfaceSnapshot.normalizedBrief(brief)
            self.grounded = grounded
        }
    }

    private var sessions: [Key: AuriUIScreenSession] = [:]
    private var archive: AuriUISurfaceSnapshotArchive
    private let onSnapshot: ((AuriUISurfaceSnapshot) -> Void)?
    private let prefetcher: AuriUIScreenPrefetcher?
    private let services: AuriUIHostServices

    public init(
        archive: AuriUISurfaceSnapshotArchive = AuriUISurfaceSnapshotArchive(),
        services: AuriUIHostServices = AuriUIHostServices(),
        onSnapshot: ((AuriUISurfaceSnapshot) -> Void)? = nil
    ) {
        self.archive = archive
        self.services = services
        self.prefetcher = services.prefetchEnabled ? AuriUIScreenPrefetcher(services: services) : nil
        self.onSnapshot = onSnapshot
    }

    public func session(parentID: String?, brief: String, grounded: Bool) -> AuriUIScreenSession {
        let key = Key(parentID: parentID, brief: brief, grounded: grounded)
        if let session = sessions[key] {
            return session
        }

        if let snapshot = archive.snapshot(brief: brief, grounded: grounded),
           let session = AuriUIScreenSession(
               snapshot: snapshot,
               parentID: parentID,
               prefetcher: prefetcher,
               services: services
           ) {
            sessions[key] = session
            return session
        }

        let session = AuriUIScreenSession(
            brief: brief,
            grounded: grounded,
            parentID: parentID,
            prefetcher: prefetcher,
            services: services,
            onReady: { [weak self] session in
                self?.sessionBecameReady(session)
            }
        )
        sessions[key] = session
        return session
    }

    private func sessionBecameReady(_ session: AuriUIScreenSession) {
        guard let snapshot = session.persistenceSnapshot,
              archive.store(snapshot) else {
            return
        }
        onSnapshot?(snapshot)
    }

    /// A canceled partial compose cannot be resumed because its streaming
    /// parser may contain a truncated document. Remove only that exact
    /// in-flight session so a later tap starts cleanly; ready and failed
    /// sessions remain stable until the owning answer leaves memory.
    public func discardIfComposing(
        _ session: AuriUIScreenSession,
        parentID: String?,
        brief: String,
        grounded: Bool
    ) {
        guard session.phase == .composing else { return }

        let key = Key(parentID: parentID, brief: brief, grounded: grounded)
        guard sessions[key] === session else { return }

        session.cancel()
        sessions.removeValue(forKey: key)
    }

    public func cancelPendingPrefetches() {
        prefetcher?.cancelPending()
    }
}

#endif
