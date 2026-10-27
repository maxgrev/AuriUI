//
//  TestSupport.swift
//  AuriUITests
//

import Foundation
import Testing
@testable import AuriUI

#if SWIFT_PACKAGE
let fixtureBundle = Bundle.module
#else
private final class TestBundleMarker: NSObject {}
let fixtureBundle = Bundle(for: TestBundleMarker.self)
#endif

/// The canonical Burger Test fixtures (see GRAMMAR.md and the Burger Test
/// acceptance criteria: these four screens are the product spec).
enum Fixture: String, CaseIterable {
    case discovery = "burger_01_discovery"
    case menu = "burger_02_menu"
    case customize = "burger_03_customize"
    case cart = "burger_04_cart"

    func text() throws -> String {
        let url = try #require(
            fixtureBundle.url(forResource: rawValue, withExtension: "aui", subdirectory: "Fixtures"),
            "Missing fixture \(rawValue).aui"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}

func splitIntoChunks(_ text: String, size: Int) -> [String] {
    precondition(size > 0)
    var chunks: [String] = []
    var index = text.startIndex
    while index < text.endIndex {
        let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
        chunks.append(String(text[index..<end]))
        index = end
    }
    return chunks
}

// Focused accessors so tests read as assertions, not pattern matches.
extension AuriUIDocument {

    var rowSections: [[AuriUITile]] {
        sections.compactMap { section in
            if case .row(_, let items) = section { return items }
            return nil
        }
    }

    var gridSections: [[AuriUITile]] {
        sections.compactMap { section in
            if case .grid(_, let items) = section { return items }
            return nil
        }
    }

    var posterSections: [[AuriUITile]] {
        sections.compactMap { section in
            if case .posters(_, let items) = section { return items }
            return nil
        }
    }

    var menuSections: [[AuriUIMenuItem]] {
        sections.compactMap { section in
            if case .menu(_, let items) = section { return items }
            return nil
        }
    }

    var lists: [AuriUIOptionList] {
        sections.compactMap { section in
            if case .list(let list) = section { return list }
            return nil
        }
    }

    var chipSections: [[AuriUIChip]] {
        sections.compactMap { section in
            if case .chips(let chips) = section { return chips }
            return nil
        }
    }

    var buttons: [AuriUIButton] {
        sections.compactMap { section in
            if case .button(let button) = section { return button }
            return nil
        }
    }

    var receiptSections: [[AuriUIReceiptLine]] {
        sections.compactMap { section in
            if case .receipt(_, let lines) = section { return lines }
            return nil
        }
    }

    var statSections: [[AuriUIStat]] {
        sections.compactMap { section in
            if case .stats(_, let items) = section { return items }
            return nil
        }
    }

    var charts: [AuriUIChart] {
        sections.compactMap { section in
            if case .chart(let chart) = section { return chart }
            return nil
        }
    }

    var tabSections: [[AuriUITab]] {
        sections.compactMap { section in
            if case .tabs(let tabs) = section { return tabs }
            return nil
        }
    }

    var hasHero: Bool {
        sections.contains { section in
            if case .hero = section { return true }
            return false
        }
    }
}
