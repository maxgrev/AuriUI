//
//  ResilienceTests.swift
//  AuriUITests
//
//  AuriUI is lossy by line: model mistakes cost one line, never the screen.
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Lossy parsing")
struct ResilienceTests {

    @Test("Bad lines drop individually; the document survives")
    func badLinesDropIndividually() {
        let text = """
        aui 1
        intro "Valid intro"
        garbagekeyword "whatever this is"
        item "orphan item with no container"
        grid "Stuff"
        item 🧈 "Butter" "1 cup, unterminated
        item 🥚 "Eggs" "2 large"
        chips
        item "Chip" "A prompt"
        """

        var parser = AuriUIStreamingParser()
        parser.consume(text)
        parser.finish()

        #expect(parser.document.sections.count == 3, "intro + grid + chips survive")
        #expect(parser.document.gridSections.first?.count == 1, "Only Eggs survives in the grid")
        #expect(parser.droppedLineCount == 3)
    }

    @Test("Answer documents: summary stays outside sections; screen stays nil")
    func answerDocumentSummary() {
        let document = AuriUIStreamingParser.parse("""
        aui 1
        summary "Goodfellas and Casino are the closest matches to your taste. Both are Scorsese crime epics."
        intro "Here's what to watch next."
        chips
        item "More like Casino"
        """)

        #expect(document.screen == nil, "No screen line → an inline chat answer")
        #expect(document.summary?.hasPrefix("Goodfellas and Casino") == true)
        #expect(document.sections.count == 2, "The summary is metadata, not a section")
    }

    @Test("Empty and comment lines are ignored, not dropped")
    func blanksAndCommentsAreFree() {
        var parser = AuriUIStreamingParser()
        parser.consume("\n\n# a comment\nintro \"Hi\"\n\n")
        parser.finish()

        #expect(parser.document.sections.count == 1)
        #expect(parser.droppedLineCount == 0)
    }

    @Test("Unknown key:value pairs and action kinds are ignored (forward compat)")
    func forwardCompatibility() {
        var parser = AuriUIStreamingParser()
        parser.consume("""
        grid "Tiles"
        item 🎬 "A film" "Great" futureflag:"v2 thing" @teleport("nowhere")
        """)
        parser.finish()

        let tile = parser.document.gridSections.first?.first
        #expect(tile?.title == "A film")
        #expect(tile?.action == nil, "Unknown action kinds degrade to no action")
        #expect(parser.droppedLineCount == 0)
    }

    @Test("Zero surviving sections means not renderable")
    func emptyDocumentIsUnusable() {
        var parser = AuriUIStreamingParser()
        parser.consume("aui 1\nscreen s \"Title\"\ngrid \"Empty\"\n")
        parser.finish()

        #expect(!parser.document.isRenderable)
    }

    @Test("Pages join tiles case- and punctuation-insensitively; orphans and duplicates drop")
    func pageReconciliation() {
        let text = """
        row "Films"
        item 🎬 "Dune: Part Two" "Sci-fi epic"
        item 🛸 "Arrival" "First contact"
        page "dune part two"
        header 🎬 "Dune: Part Two" "2024"
        page "Unknown Movie"
        bullets
        item "Orphan page content"
        page "ARRIVAL"
        stats
        item "8.0" "IMDb"
        page "arrival!"
        bullets
        item "Duplicate page, first wins"
        """

        var parser = AuriUIStreamingParser()
        parser.consume(text)
        parser.finish()

        #expect(parser.document.pages.map(\.forTitle) == ["Dune: Part Two", "Arrival"])
        guard case .stats? = parser.document.pages.last?.sections.first else {
            Issue.record("The first 'Arrival' page must win")
            return
        }
    }

    @Test("Pages join compare column titles — every contender gets a detail page")
    func pagesJoinCompareColumns() {
        let text = """
        compare 🥊
        col "Tesla Model 3" img:"tesla model 3 press photo"
        col "Hyundai Ioniq 5" img:"hyundai ioniq 5 press photo"
        crow "Range" "309–363 mi" "up to 318 mi" win:1
        page "tesla model 3"
        stats
        item "$38.6K" "Price"
        page "Hyundai Ioniq 5"
        stats
        item "$35.0K" "Price"
        """

        var parser = AuriUIStreamingParser()
        parser.consume(text)
        parser.finish()

        #expect(parser.document.pages.map(\.forTitle) == ["Tesla Model 3", "Hyundai Ioniq 5"])
    }

    @Test("Tabs close implicitly at end of stream; nested tabs lines drop")
    func tabsAreResilient() {
        let text = """
        tabs
        tab "Weekend"
        bullets
        item "Short trip"
        tabs
        tab "Full week"
        bullets
        item "Long trip"
        """

        var parser = AuriUIStreamingParser()
        parser.consume(text)
        parser.finish()

        let tabs = parser.document.tabSections.first
        #expect(tabs?.map(\.title) == ["Weekend", "Full week"])
        #expect(parser.droppedLineCount == 1, "The nested `tabs` line drops")
    }

    @Test("Sections between `tabs` and the first `tab` have no home and drop")
    func homelessTabSectionsDrop() {
        var parser = AuriUIStreamingParser()
        parser.consume("tabs\nintro \"Homeless\"\ntab \"One\"\nbullets\nitem \"A\"\nend\n")
        parser.finish()

        #expect(parser.document.tabSections.first?.count == 1)
        #expect(parser.droppedLineCount == 1)
    }

    @Test("A `screen` line after content drops; the first header wins")
    func lateScreenLineDrops() {
        var parser = AuriUIStreamingParser()
        parser.consume("screen first \"First\"\nintro \"Hi\"\nscreen second \"Second\"\n")
        parser.finish()

        #expect(parser.document.screen?.id == "first")
        #expect(parser.droppedLineCount == 1)
    }
}
