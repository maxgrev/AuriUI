//
//  SurfaceSnapshotTests.swift
//  AuriUITests
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Surface snapshot persistence")
struct SurfaceSnapshotTests {

    @Test("Equivalent briefs resolve the same persisted surface")
    func normalizedIdentity() {
        let snapshot = makeSnapshot(brief: "  Napa &   Sonoma\nweekend ")
        let archive = AuriUISurfaceSnapshotArchive(snapshots: [snapshot])

        #expect(archive.snapshot(brief: "napa & sonoma weekend", grounded: true) == snapshot)
        #expect(archive.snapshot(brief: "napa & sonoma weekend", grounded: false) == nil)
    }

    @Test("Storing an identical surface does not request another persistence write")
    func duplicateStoreIsNoOp() {
        let snapshot = makeSnapshot(brief: "Yosemite")
        var archive = AuriUISurfaceSnapshotArchive()

        let firstStoreChanged = archive.store(snapshot)
        let duplicateStoreChanged = archive.store(snapshot)
        #expect(firstStoreChanged)
        #expect(!duplicateStoreChanged)
        #expect(archive.snapshots == [snapshot])
    }

    @Test("Replacing a surface keeps only its latest completed content")
    func replacement() {
        let first = makeSnapshot(brief: "Monterey", title: "First")
        let replacement = makeSnapshot(brief: "Monterey", title: "Replacement")
        var archive = AuriUISurfaceSnapshotArchive(snapshots: [first])

        let changed = archive.store(replacement)
        #expect(changed)
        #expect(archive.snapshots == [replacement])
    }

    @Test("Archive evicts oldest surfaces to remain bounded")
    func boundedArchive() {
        let first = makeSnapshot(brief: "First")
        let second = makeSnapshot(brief: "Second")
        let third = makeSnapshot(brief: "Third")
        var archive = AuriUISurfaceSnapshotArchive()

        archive.store(first, maximumCount: 2)
        archive.store(second, maximumCount: 2)
        archive.store(third, maximumCount: 2)

        #expect(archive.snapshots == [second, third])
    }

    @Test("Unsupported snapshots are ignored")
    func unsupportedVersion() {
        let snapshot = AuriUISurfaceSnapshot(
            version: AuriUISurfaceSnapshot.currentVersion + 1,
            brief: "Future screen",
            grounded: true,
            auiText: "aui 1"
        )
        var archive = AuriUISurfaceSnapshotArchive()

        let changed = archive.store(snapshot)
        #expect(!changed)
        #expect(archive.snapshots.isEmpty)
    }

    @Test("Snapshot encoding preserves the authoritative document and resources")
    func codableRoundTrip() throws {
        let snapshot = makeSnapshot(brief: "Lake Tahoe")

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AuriUISurfaceSnapshot.self, from: encoded)

        #expect(decoded == snapshot)
    }

    @Test("Persisted archive JSON restores the same bounded snapshot set")
    func archiveJSONRoundTrip() throws {
        let snapshots = [
            makeSnapshot(brief: "Napa"),
            makeSnapshot(brief: "Yosemite"),
        ]
        let archive = AuriUISurfaceSnapshotArchive(snapshots: snapshots)
        let json = try #require(archive.jsonString)

        let restored = AuriUISurfaceSnapshotArchive(jsonString: json)

        #expect(restored == archive)
    }

    private func makeSnapshot(
        brief: String,
        title: String = "Wine Country"
    ) -> AuriUISurfaceSnapshot {
        AuriUISurfaceSnapshot(
            brief: brief,
            grounded: true,
            auiText: """
            aui 1
            screen wine "\(title)"
            intro "Stable generated content"
            """,
            resources: ["r1": "https://example.com"]
        )
    }
}
