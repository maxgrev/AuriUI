//
//  SelectionStateTests.swift
//  AuriUITests
//
//  The unit-level Burger Test: totals are exact, deterministic, and computed
//  only by the client. These are the demo's numbers — $12.50 base, +$2.00
//  bacon, $2.99 delivery, $17.49 total.
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Selection state — the Burger Test arithmetic")
struct SelectionStateTests {

    private func customizeState() throws -> (AuriUIDocument, AuriUISelectionState) {
        let document = AuriUIStreamingParser.parse(try Fixture.customize.text())
        return (document, AuriUISelectionState(document: document))
    }

    @Test("Defaults: included bun and cheese, base price total")
    func defaults() throws {
        let (_, state) = try customizeState()

        #expect(state.isSelected(group: "bun", value: "brioche"))
        #expect(state.isSelected(group: "cheese", value: "american"))
        #expect(!state.isToggled(value: "bacon"))
        #expect(state.formattedTotal() == "$12.50")
        #expect(state.selectionSummary == "Brioche, American")
    }

    @Test("Toggling bacon lands on the demo's exact number")
    func baconMath() throws {
        var (_, state) = try customizeState()

        state.toggle(value: "bacon")
        #expect(state.formattedTotal() == "$14.50")

        state.toggle(value: "bacon")
        #expect(state.formattedTotal() == "$12.50", "Toggling off restores the base exactly")
    }

    @Test("Every option contributes its exact price")
    func fullHouse() throws {
        var (_, state) = try customizeState()

        state.select(group: "bun", value: "lettuce")     // +1.00
        state.select(group: "cheese", value: "pepperjack") // +0.50
        state.toggle(value: "bacon")                      // +2.00
        state.toggle(value: "avocado")                    // +2.50
        state.toggle(value: "onions")                     // +1.00

        #expect(state.total == Decimal(string: "19.50", locale: Locale(identifier: "en_US_POSIX")))
        #expect(state.formattedTotal() == "$19.50")
    }

    @Test("Unknown groups and values are no-ops")
    func unknownSelectionsAreNoOps() throws {
        var (_, state) = try customizeState()

        state.select(group: "bun", value: "pretzel")
        state.select(group: "sauce", value: "ketchup")
        state.toggle(value: "goldleaf")

        #expect(state.isSelected(group: "bun", value: "brioche"), "A bad value must not deselect the bun")
        #expect(state.formattedTotal() == "$12.50")
    }

    @Test("CTA label interpolation renders the running total")
    func labelInterpolation() throws {
        var (document, state) = try customizeState()
        state.toggle(value: "bacon")

        let cta = try #require(document.buttons.first)
        #expect(state.interpolate(cta.label) == "Add to order · $14.50")
    }

    @Test("Nav briefs carry the exact configuration for the next composer to copy")
    func navBriefInterpolation() throws {
        var (document, state) = try customizeState()
        state.toggle(value: "bacon")

        let cta = try #require(document.buttons.first)
        let action = try #require(cta.action)
        guard case .nav(let brief) = state.interpolated(action) else {
            Issue.record("The CTA must navigate to the cart")
            return
        }

        #expect(brief.contains("1× Classic Smash — Brioche, American, Applewood bacon"))
        #expect(brief.contains("priced $14.50"))
        #expect(!brief.contains("{"), "No placeholder may leak into a dispatched action")
    }

    @Test("Cart receipt sums client-side to the demo's exact total")
    func cartReceiptTotal() throws {
        let document = AuriUIStreamingParser.parse(try Fixture.cart.text())
        let state = AuriUISelectionState(document: document)

        #expect(state.total == Decimal(string: "17.49", locale: Locale(identifier: "en_US_POSIX")))
        #expect(state.formattedTotal() == "$17.49")

        let cta = try #require(document.buttons.first)
        #expect(state.interpolate(cta.label) == "Place order · $17.49")
    }

    @Test("Price tags: Included for zero, signed currency otherwise")
    func priceTags() throws {
        let (_, state) = try customizeState()

        #expect(state.priceTag(for: 0) == "Included")
        #expect(state.priceTag(for: 2) == "+$2.00")
        #expect(state.formattedPrice(2) == "$2.00")
        #expect(state.priceTag(for: Decimal(string: "0.50", locale: Locale(identifier: "en_US_POSIX"))!) == "+$0.50")
        #expect(state.priceTag(for: -1) == "−$1.00")
    }

    @Test("Receipts itemize everything: a stray state base cannot double-count")
    func receiptsIgnoreBase() {
        // Live composers sometimes copy the item price into `state base`
        // AND itemize it as a receipt line ($18 burger totalling $38.99).
        let document = AuriUIStreamingParser.parse("""
        screen cart "Your order"
        state base:18.00 cur:USD
        receipt "Order summary"
        item "1× Double Decker" price:18.00
        item "Delivery fee" price:2.99
        button primary "Place order · {total}"
        """)
        let state = AuriUISelectionState(document: document)

        #expect(state.formattedTotal() == "$20.99", "Receipt lines are the whole truth on cart screens")
    }

    @Test("The whole pipeline is deterministic across 10 runs — 10/10, not 9/10")
    func tenOutOfTen() throws {
        var results = Set<String>()

        for _ in 1...10 {
            let document = AuriUIStreamingParser.parse(try Fixture.customize.text())
            var state = AuriUISelectionState(document: document)
            state.toggle(value: "bacon")
            let cta = document.buttons.first
            results.insert("\(state.interpolate(cta?.label ?? "")) | \(state.selectionSummary)")
        }

        #expect(results == ["Add to order · $14.50 | Brioche, American, Applewood bacon"])
    }
}
