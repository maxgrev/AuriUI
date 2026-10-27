//
//  StreamingTests.swift
//  AuriUITests
//
//  The renderer draws while tokens stream, so parsing must be byte-boundary
//  agnostic and strictly progressive.
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Streaming")
struct StreamingTests {

    @Test(
        "Chunked parsing is identical to whole-text parsing at any boundary",
        arguments: Fixture.allCases, [1, 3, 7, 16, 64]
    )
    func chunkBoundaryEquivalence(fixture: Fixture, chunkSize: Int) throws {
        let text = try fixture.text()
        let reference = AuriUIStreamingParser.parse(text)

        var parser = AuriUIStreamingParser()
        for chunk in splitIntoChunks(text, size: chunkSize) {
            parser.consume(chunk)
        }
        parser.finish()

        #expect(parser.document == reference)
        #expect(parser.droppedLineCount == 0)
    }

    @Test("Sections appear progressively, hero first")
    func progressiveReveal() throws {
        let lines = try Fixture.customize.text().split(separator: "\n", omittingEmptySubsequences: false)
        var parser = AuriUIStreamingParser()
        var sectionCounts: [Int] = []

        for line in lines {
            parser.consume(String(line) + "\n")
            sectionCounts.append(parser.document.sections.count)
        }
        parser.finish()

        // The hero renders before any list finishes (line 4 of the fixture).
        let heroVisibleAt = try #require(sectionCounts.firstIndex(where: { $0 >= 1 }))
        #expect(heroVisibleAt <= 3, "First paint must not wait for the document to complete")

        // Counts never regress: streaming only ever adds content.
        #expect(sectionCounts == sectionCounts.sorted())
        #expect(parser.document.sections.count == 5)
    }

    @Test("Open-container items surface item by item")
    func openContainerItemsAreVisible() {
        var parser = AuriUIStreamingParser()
        parser.consume("grid \"What you need\"\n")
        parser.consume("item 🧈 \"Butter\" \"1 cup, melted\"\n")
        #expect(parser.document.gridSections.first?.count == 1)

        parser.consume("item 🥚 \"Eggs\" \"2 large\"\n")
        #expect(parser.document.gridSections.first?.count == 2)
    }

    @Test("consume reports whether the document changed")
    func consumeChangeReporting() {
        var parser = AuriUIStreamingParser()
        #expect(parser.consume("aui 1\n") == false, "The version header renders nothing")
        #expect(parser.consume("intro \"Hello\"\n") == true)
        #expect(parser.consume("item \"orphan\"\n") == false, "A dropped line changes nothing")
    }

    @Test("A stream cut mid-line still yields the completed sections")
    func truncatedStreamSurvives() throws {
        let text = try Fixture.customize.text()
        let cut = text.index(text.startIndex, offsetBy: text.count * 2 / 3)

        var parser = AuriUIStreamingParser()
        parser.consume(String(text[..<cut]))
        parser.finish()

        #expect(parser.document.isRenderable)
        #expect(parser.document.screen != nil)
    }

    @Test("finish flushes a final line with no trailing newline")
    func finishFlushesTrailingLine() {
        var parser = AuriUIStreamingParser()
        parser.consume("bullets\nitem \"First\"\nitem \"Last line has no newline\"")
        parser.finish()

        guard case .bullets(_, _, let items)? = parser.document.sections.first else {
            Issue.record("Expected a bullets section")
            return
        }
        #expect(items == ["First", "Last line has no newline"])
    }
}
