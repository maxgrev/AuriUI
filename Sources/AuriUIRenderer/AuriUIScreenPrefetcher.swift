#if os(iOS) || os(macOS)
//
//  AuriUIScreenPrefetcher.swift
//  Auri
//
//  The speculation engine: once a surface is on screen, every reachable
//  @nav brief describes its next screen — so compose them in the background
//  and taps land instantly. Generalizes the v1 detail-pages trick into the
//  core interaction model.
//

import AuriUI
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class AuriUIScreenPrefetcher {

    private struct Request {
        let key: String
        let parentID: String
        let brief: String
        let generation: Int
    }

    private var cache: [String: AuriUISurfaceSnapshot] = [:]
    /// Insertion-ordered keys for LRU eviction.
    private var cacheOrder: [String] = []
    private var inflight: [String: Task<Void, Never>] = [:]
    private var queue: [Request] = []

    private let maxCachedScreens = 12
    private let maxConcurrentComposes = 2
    private let maxCandidatesPerScreen = 6
    private var activeParentID: String?
    private var generation = 0
    private let services: AuriUIHostServices

    public init(services: AuriUIHostServices = AuriUIHostServices()) {
        self.services = services
    }

    /// Instant screen for a brief the engine already composed, if any.
    public func cachedSnapshot(
        for brief: String,
        grounded: Bool,
        parentID: String
    ) -> AuriUISurfaceSnapshot? {
        let key = Self.key(parentID: parentID, brief: brief, grounded: grounded)
        guard let snapshot = cache[key] else {
            return nil
        }
        // Refresh LRU position.
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return snapshot
    }

    /// Queues screens worth speculating. Briefs with unexpanded placeholders
    /// depend on live selection state and change under the user's fingers, so
    /// they are skipped — composing them would race the selections.
    public func prefetch(briefs: [String], parentID: String) {
        guard services.prefetchEnabled, services.stream != nil else { return }
        activate(parentID: parentID)

        var acceptedCount = 0
        for brief in briefs {
            guard acceptedCount < maxCandidatesPerScreen else { break }
            let key = Self.key(parentID: parentID, brief: brief, grounded: false)
            guard !brief.isEmpty,
                  !brief.contains("{"),
                  cache[key] == nil,
                  inflight[key] == nil,
                  !queue.contains(where: { $0.key == key }) else {
                continue
            }
            queue.append(Request(
                key: key,
                parentID: parentID,
                brief: brief,
                generation: generation
            ))
            acceptedCount += 1
        }
        pump()
    }

    /// Drops queued and in-flight work (surface stack dismissed). The cache
    /// survives — re-opening a flow stays instant.
    public func cancelPending() {
        generation += 1
        activeParentID = nil
        queue.removeAll()
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
    }

    private func activate(parentID: String) {
        guard activeParentID != parentID else { return }
        generation += 1
        activeParentID = parentID
        queue.removeAll()
        for task in inflight.values {
            task.cancel()
        }
        inflight.removeAll()
    }

    private func pump() {
        while inflight.count < maxConcurrentComposes, !queue.isEmpty {
            let request = queue.removeFirst()
            inflight[request.key] = Task { [weak self] in
                await self?.compose(request)
                guard self?.generation == request.generation else { return }
                self?.inflight[request.key] = nil
                self?.pump()
            }
        }
    }

    private func compose(_ request: Request) async {
        do {
            var resources: [String: URL] = [:]
            // Speculated screens are always @nav children: facts arrive in
            // the brief, so skip the grounding hop.
            guard let stream = services.stream else { return }
            for try await event in stream(AuriUIStreamRequest(brief: request.brief, grounded: false)) {
                try Task.checkCancellation()
                switch event {
                case .resources(let resolved):
                    resources.merge(resolved) { _, new in new }
                case .document(let text, _):
                    let document = AuriUIStreamingParser.parse(text)
                    guard !Task.isCancelled,
                          activeParentID == request.parentID,
                          generation == request.generation,
                          document.isRenderable else {
                        return
                    }
                    store(AuriUISurfaceSnapshot(
                        brief: request.brief,
                        grounded: false,
                        auiText: text,
                        resources: resources.mapValues(\.absoluteString)
                    ), key: request.key)
                    return
                case .designing, .delta:
                    break
                }
            }
        } catch {
            // Speculation is best-effort: a failed pre-compose just means
            // the tap composes live, exactly as if we'd never speculated.
        }
    }

    private func store(_ snapshot: AuriUISurfaceSnapshot, key: String) {
        if cache[key] == nil {
            cacheOrder.append(key)
        }
        cache[key] = snapshot
        while cacheOrder.count > maxCachedScreens {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private static func key(parentID: String, brief: String, grounded: Bool) -> String {
        "\(parentID)|\(grounded ? "grounded" : "inherited")|\(AuriUISurfaceSnapshot.normalizedBrief(brief))"
    }
}

#endif
