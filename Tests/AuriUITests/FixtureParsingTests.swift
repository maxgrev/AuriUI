//
//  FixtureParsingTests.swift
//  AuriUITests
//
//  The burger fixtures are the product spec: every screen must parse fully,
//  losslessly, and within the token budget.
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Burger fixtures — universal guarantees")
struct FixtureUniversalTests {

    @Test("Every fixture parses losslessly into a renderable screen", arguments: Fixture.allCases)
    func parsesCleanly(fixture: Fixture) throws {
        var parser = AuriUIStreamingParser()
        parser.consume(try fixture.text())
        parser.finish()

        #expect(parser.document.isRenderable)
        #expect(parser.document.screen != nil, "Burger fixtures are screens, not answers")
        #expect(parser.droppedLineCount == 0, "A hand-written fixture must not lose a single line")
    }

    @Test("Every fixture stays within the ~500-token screen budget", arguments: Fixture.allCases)
    func staysWithinTokenBudget(fixture: Fixture) throws {
        // ~4 chars/token: the Sushi Test's wire-size bar (≤ 500 tokens).
        let characterCount = try fixture.text().count
        #expect(characterCount <= 2_000, "\(fixture.rawValue) is \(characterCount) chars (~\(characterCount / 4) tokens)")
    }
}

@Suite("Burger fixtures — per-screen structure")
struct FixtureStructureTests {

    @Test("Discovery: hero, three restaurant tiles with nav briefs, chips, primary CTA")
    func discovery() throws {
        let document = AuriUIStreamingParser.parse(try Fixture.discovery.text())

        let header = try #require(document.screen)
        #expect(header.id == "food_nearby")
        #expect(header.title == "Order food")
        #expect(document.hasHero)

        let tiles = try #require(document.rowSections.first)
        #expect(tiles.count == 3)
        #expect(tiles.map(\.title) == ["The Daily Grill", "Sakura Zen", "Tuk Tuk Thai"])
        for tile in tiles {
            #expect(tile.imageQuery != nil)
            guard case .nav(let brief) = tile.action else {
                Issue.record("\(tile.title) must navigate to a menu screen")
                continue
            }
            #expect(brief.contains("Menu screen"), "Nav briefs must be self-contained screen briefs")
        }

        #expect(document.chipSections.first?.count == 2)
        let cta = try #require(document.buttons.first)
        #expect(cta.isPrimary)
        if case .nav = cta.action {} else {
            Issue.record("Order-the-usual must nav to a cart screen")
        }
    }

    @Test("Menu: delivery stats, commerce rows with prices and customization briefs")
    func menu() throws {
        let document = AuriUIStreamingParser.parse(try Fixture.menu.text())

        #expect(document.screen?.id == "daily_grill_menu")
        #expect(document.screen?.tint == "amber", "Flows carry one art-direction tint")
        #expect(document.statSections.first?.count == 3)

        let burgers = try #require(document.menuSections.first)
        #expect(burgers.map(\.title) == ["Classic Smash", "Double Bacon"])
        #expect(burgers.map(\.price) == [
            Decimal(string: "12.50", locale: Locale(identifier: "en_US_POSIX")),
            Decimal(string: "15.00", locale: Locale(identifier: "en_US_POSIX")),
        ])
        #expect(burgers[0].badge == "Bestseller")

        guard case .nav(let brief) = burgers[0].action else {
            Issue.record("Classic Smash must open its customization screen")
            return
        }
        #expect(brief.contains("$12.50 base"))
        #expect(brief.contains("Applewood bacon +$2.00"), "The brief carries exact prices for the composer to copy")

        #expect(document.gridSections.first?.count == 2)
    }

    @Test("Posters: cover carousels parse with badges and join detail pages")
    func posters() {
        let document = AuriUIStreamingParser.parse("""
        posters "Top picks"
        item "Dune: Part Two" img:"dune part two movie poster" cap:"2024 · 8.5★" badge:"New"
        item "Arrival" img:"arrival movie poster" cap:"2016"
        page "Dune: Part Two"
        header 🎬 "Dune: Part Two" "2024 · Sci-fi epic"
        """)

        let posters = document.posterSections.first
        #expect(posters?.map(\.title) == ["Dune: Part Two", "Arrival"])
        #expect(posters?.first?.badge == "New")
        #expect(document.pages.map(\.forTitle) == ["Dune: Part Two"], "Poster tiles anchor detail pages")
    }

    @Test("Customize: base price, two pick groups, one multi list, {total} CTA")
    func customize() throws {
        let document = AuriUIStreamingParser.parse(try Fixture.customize.text())

        #expect(document.screen?.id == "customize_classic_smash")
        #expect(document.money.base == Decimal(string: "12.50", locale: Locale(identifier: "en_US_POSIX")))
        #expect(document.money.currencyCode == "USD")

        let lists = document.lists
        try #require(lists.count == 3)
        #expect(lists[0].mode == .pick(group: "bun"))
        #expect(lists[1].mode == .pick(group: "cheese"))
        #expect(lists[2].mode == .multi)
        #expect(lists.flatMap(\.items).count == 8)

        let bun = lists[0]
        #expect(bun.items.first?.selectedByDefault == true, "Brioche is the default bun")
        #expect(bun.items.map(\.selectionValue) == ["brioche", "potato", "lettuce"])
        #expect(bun.items.map(\.price) == [0, 0, Decimal(1)])

        let cta = try #require(document.buttons.first)
        #expect(cta.label.contains("{total}"), "The CTA renders the client-computed running total")
        guard case .nav(let brief) = cta.action else {
            Issue.record("Add-to-order must nav to the cart")
            return
        }
        #expect(brief.contains("{selections}"))
        #expect(brief.contains("{total}"))
    }

    @Test("Nav briefs surface every reachable next screen, in document order")
    func navBriefs() throws {
        let discovery = AuriUIStreamingParser.parse(try Fixture.discovery.text())
        #expect(discovery.navBriefs.count == 4, "Three restaurant tiles plus the order-the-usual CTA")
        #expect(discovery.navBriefs.first?.contains("The Daily Grill") == true)

        let customize = AuriUIStreamingParser.parse(try Fixture.customize.text())
        #expect(customize.navBriefs.count == 1)
        #expect(customize.navBriefs.first?.contains("{selections}") == true,
                "Placeholder briefs pass through raw; callers decide to expand or skip")
    }

    @Test("Comparisons: col lines carry contender images; rows need 2+ columns")
    func comparisonColumns() {
        let document = AuriUIStreamingParser.parse("""
        compare 🥊
        col "Tesla Model 3" img:"tesla model 3 press photo"
        col "Hyundai Ioniq 5" img:"hyundai ioniq 5 press photo"
        cgroup "Range and charging"
        crow "Range" "309–363 mi" "up to 318 mi" win:1 n1:"More range" n2:"Less range"
        """)

        guard case .compare(let comparison)? = document.sections.first else {
            Issue.record("Expected a comparison section")
            return
        }
        #expect(comparison.columns.map(\.title) == ["Tesla Model 3", "Hyundai Ioniq 5"])
        #expect(comparison.columns.first?.imageQuery == "tesla model 3 press photo")
        #expect(comparison.groups.first?.rows.first?.winner == 1)
        #expect(comparison.groups.first?.rows.first?.notes == ["More range", "Less range"])

        let single = AuriUIStreamingParser.parse("""
        compare
        col "Alone"
        crow "Range" "300 mi"
        """)
        #expect(single.sections.isEmpty, "A one-column comparison cannot render")

        let triple = AuriUIStreamingParser.parse("""
        compare
        col "Tesla Model 3" img:"tesla model 3"
        col "Hyundai Ioniq 5" img:"hyundai ioniq 5"
        col "Kia EV6" img:"kia ev6"
        crow "Starting price" "$38.6K" "$35.0K" "$44.4K" win:2
        crow "Range" "309–363 mi" "up to 318 mi"
        """)
        guard case .compare(let wide)? = triple.sections.first else {
            Issue.record("Expected a three-column comparison")
            return
        }
        #expect(wide.columns.count == 3)
        #expect(wide.groups.first?.rows.first?.values.count == 3)
        #expect(wide.groups.first?.rows.last?.values == ["309–363 mi", "up to 318 mi", ""],
                "Missing trailing values pad to the column count")
    }

    @Test("Detailed comparison benchmark: decision breadth, badges, and useful pages")
    func detailedComparisonBenchmark() throws {
        let url = try #require(
            fixtureBundle.url(
                forResource: "ev_comparison_detailed",
                withExtension: "aui",
                subdirectory: "Fixtures"
            )
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AuriUIStreamingParser()
        parser.consume(text)
        parser.finish()

        #expect(parser.droppedLineCount == 0)
        #expect(parser.document.summary?.contains("better buy") == true)
        #expect(!parser.document.hasHero, "Comparison columns are the main answer's visual anchor")

        let comparison = try #require(parser.document.sections.compactMap { section in
            if case .compare(let comparison) = section { return comparison }
            return nil
        }.first)
        #expect(comparison.groups.count == 5)
        #expect(comparison.groups.flatMap(\.rows).count == 11)
        #expect(comparison.groups.flatMap(\.rows).flatMap(\.notes).compactMap { $0 }.count >= 10)
        #expect(parser.document.pages.map(\.forTitle) == ["Rivian R2", "Tesla Model Y"])
        #expect(parser.document.pages.allSatisfy { $0.sections.count >= 6 })
    }

    @Test("Facts: icon-led feature rows parse like steps, render editorial")
    func facts() {
        let document = AuriUIStreamingParser.parse("""
        facts "Why it wins"
        item 🔌 "Road trip easy" "Supercharger access keeps charging simple."
        item 🌬 "Efficiency leader" "Excellent range for the price."
        """)

        guard case .facts(let title, let items)? = document.sections.first else {
            Issue.record("Expected a facts section")
            return
        }
        #expect(title == "Why it wins")
        #expect(items.map(\.title) == ["Road trip easy", "Efficiency leader"])
        #expect(items.first?.emoji == "🔌")
    }

    @Test("Tables: neutral columns, stable cells, and highlighted rows")
    func tables() {
        let document = AuriUIStreamingParser.parse("""
        table "League table"
        tcol "Team"
        tcol "P"
        tcol "GD"
        tcol "Pts"
        trow "Arsenal" "32" "+42" "74" hi
        trow "Liverpool" "32" "+40" "71"
        """)

        guard case .table(let table)? = document.sections.first else {
            Issue.record("Expected a table section")
            return
        }
        #expect(table.title == "League table")
        #expect(table.columns.map(\.title) == ["Team", "P", "GD", "Pts"])
        #expect(table.rows.map(\.values) == [
            ["Arsenal", "32", "+42", "74"],
            ["Liverpool", "32", "+40", "71"],
        ])
        #expect(table.rows.first?.isHighlighted == true)
        #expect(Set(table.rows.flatMap(\.cells).map(\.id)).count == 4,
                "Cells align to stable column identities across rows")
    }

    @Test("Cart: receipt lines carry exact prices; CTA totals via {total}")
    func cart() throws {
        let document = AuriUIStreamingParser.parse(try Fixture.cart.text())

        #expect(document.screen?.id == "daily_grill_cart")

        let lines = try #require(document.receiptSections.first)
        #expect(lines.count == 2)
        #expect(lines[0].label.contains("Classic Smash"))
        #expect(lines[0].price == Decimal(string: "14.50", locale: Locale(identifier: "en_US_POSIX")))
        #expect(lines[1].price == Decimal(string: "2.99", locale: Locale(identifier: "en_US_POSIX")))

        let cta = try #require(document.buttons.first)
        #expect(cta.label.contains("{total}"))
    }
}
