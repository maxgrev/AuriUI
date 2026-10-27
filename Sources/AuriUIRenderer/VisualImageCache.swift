#if os(iOS) || os(macOS)
//
//  VisualImageCache.swift
//  Auri
//
//  Temporary, bounded image storage for generated Visual surfaces. Search
//  photos are remote presentation assets, not user documents: keep them in
//  the OS-managed Caches area so reopened chats stay visual without adding
//  them to permanent chat or generated-image storage.
//

import Foundation

@available(iOS 17.0, macOS 14.0, *)
actor VisualImageCache {

    static let shared = VisualImageCache()

    private struct Download: Sendable {
        let data: Data
        let mimeType: String?
    }

    enum CacheError: Error, Equatable {
        case invalidResponse
        case invalidImagePayload
        case payloadTooLarge
    }

    private static let cachedAtKey = "auri_visual_cached_at"
    private static let timeToLive: TimeInterval = 24 * 60 * 60
    private static let maximumPayloadBytes = 20 * 1_024 * 1_024

    private let cache: URLCache
    private let session: URLSession
    private var inFlight: [URL: Task<Download, Error>] = [:]

    init(session: URLSession? = nil) {
        let cache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 160 * 1_024 * 1_024,
            directory: URL.cachesDirectory.appending(path: "org.auriui.images", directoryHint: .isDirectory)
        )
        self.cache = cache

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: configuration)
    }

    func data(for url: URL) async throws -> Data {
        // Local assets make offline hosts and the bundled demo self-contained.
        // File I/O runs on this actor rather than the main actor.
        if url.isFileURL {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= Self.maximumPayloadBytes else {
                throw CacheError.payloadTooLarge
            }
            return try Data(contentsOf: url)
        }

        let request = URLRequest(url: url)
        if let cached = freshCachedResponse(for: request) {
            return cached.data
        }

        if let existing = inFlight[url] {
            return try await existing.value.data
        }

        let session = session
        let task = Task<Download, Error> {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw CacheError.invalidResponse
            }
            guard response.expectedContentLength <= Self.maximumPayloadBytes else {
                throw CacheError.payloadTooLarge
            }
            if let mimeType = response.mimeType,
               !mimeType.lowercased().hasPrefix("image/") {
                throw CacheError.invalidImagePayload
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maximumPayloadBytes else {
                    throw CacheError.payloadTooLarge
                }
                data.append(byte)
            }
            return Download(data: data, mimeType: response.mimeType)
        }
        inFlight[url] = task

        do {
            let download = try await task.value
            inFlight[url] = nil
            store(download, for: request)
            return download.data
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private func freshCachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard let response = cache.cachedResponse(for: request),
              response.data.count <= Self.maximumPayloadBytes,
              let cachedAt = response.userInfo?[Self.cachedAtKey] as? TimeInterval,
              Date().timeIntervalSince1970 - cachedAt < Self.timeToLive else {
            cache.removeCachedResponse(for: request)
            return nil
        }
        return response
    }

    private func store(_ download: Download, for request: URLRequest) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Cache-Control": "private, max-age=86400",
                    "Content-Type": download.mimeType ?? "image/*",
                    "Content-Length": String(download.data.count),
                ]
              ) else {
            return
        }
        cache.storeCachedResponse(
            CachedURLResponse(
                response: response,
                data: download.data,
                userInfo: [Self.cachedAtKey: Date().timeIntervalSince1970],
                storagePolicy: .allowed
            ),
            for: request
        )
    }
}
#endif
