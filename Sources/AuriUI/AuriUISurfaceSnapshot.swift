//
//  AuriUISurfaceSnapshot.swift
//  AuriUI
//
//  A durable representation of one completed generated surface. The raw
//  AuriUI document remains the source of truth so restored screens use the
//  same parser and renderer as freshly composed screens.
//

import Foundation

public struct AuriUISurfaceSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let brief: String
    public let grounded: Bool
    public let auiText: String
    public let resources: [String: String]

    public init(
        version: Int = Self.currentVersion,
        brief: String,
        grounded: Bool,
        auiText: String,
        resources: [String: String] = [:]
    ) {
        self.version = version
        self.brief = brief
        self.grounded = grounded
        self.auiText = auiText
        self.resources = resources
    }

    public var identity: String {
        "\(grounded ? "grounded" : "inherited")|\(Self.normalizedBrief(brief))"
    }

    public var isCompatible: Bool {
        version == Self.currentVersion
            && !Self.normalizedBrief(brief).isEmpty
            && !auiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var approximateByteCount: Int {
        brief.utf8.count
            + auiText.utf8.count
            + resources.reduce(into: 0) { count, entry in
                count += entry.key.utf8.count + entry.value.utf8.count
            }
    }

    public func matches(brief: String, grounded: Bool) -> Bool {
        self.grounded == grounded
            && Self.normalizedBrief(self.brief) == Self.normalizedBrief(brief)
    }

    public static func normalizedBrief(_ brief: String) -> String {
        brief
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}

/// Bounded, insertion-ordered snapshots belonging to one persisted answer.
/// Replacing a screen moves it to the end; the oldest screens are evicted
/// first if a long flow exceeds the Firestore-safe budget.
public struct AuriUISurfaceSnapshotArchive: Equatable, Sendable {
    public static let maximumSnapshotCount = 12
    public static let maximumApproximateBytes = 96 * 1_024

    public private(set) var snapshots: [AuriUISurfaceSnapshot]

    public init(snapshots: [AuriUISurfaceSnapshot] = []) {
        self.snapshots = []
        for snapshot in snapshots {
            store(snapshot)
        }
    }

    public init(jsonString: String?) {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AuriUISurfaceSnapshot].self, from: data) else {
            self.init()
            return
        }
        self.init(snapshots: decoded)
    }

    public var jsonString: String? {
        guard !snapshots.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshots) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func snapshot(brief: String, grounded: Bool) -> AuriUISurfaceSnapshot? {
        snapshots.last { $0.isCompatible && $0.matches(brief: brief, grounded: grounded) }
    }

    @discardableResult
    public mutating func store(
        _ snapshot: AuriUISurfaceSnapshot,
        maximumCount: Int = Self.maximumSnapshotCount,
        maximumApproximateBytes: Int = Self.maximumApproximateBytes
    ) -> Bool {
        guard snapshot.isCompatible,
              maximumCount > 0,
              snapshot.approximateByteCount <= maximumApproximateBytes else {
            return false
        }

        if let existing = snapshots.first(where: { $0.identity == snapshot.identity }),
           existing == snapshot {
            return false
        }

        var updated = snapshots.filter { $0.identity != snapshot.identity }
        updated.append(snapshot)

        while updated.count > maximumCount
            || updated.reduce(0, { $0 + $1.approximateByteCount }) > maximumApproximateBytes {
            updated.removeFirst()
        }

        snapshots = updated
        return true
    }
}
