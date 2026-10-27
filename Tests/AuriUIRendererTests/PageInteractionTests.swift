#if os(iOS) || os(macOS)
import AuriUI
import AuriUIRenderer
import Foundation
import Testing

@MainActor
@Suite("Detail page interactions")
struct PageInteractionTests {
    @Test("Page options and prices stay local and survive closing and reopening")
    func pageSelectionIsolation() throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        let root = AuriUIScreenSession(answerText: Self.lunch)
        let soupPage = try #require(root.page(for: "Soup"))
        let saladPage = try #require(root.page(for: "Salad"))
        let soup = root.pageSession(for: soupPage)
        let salad = root.pageSession(for: saladPage)

        #expect(root.selection.total == 7)
        #expect(soup.selection.total == 6)
        #expect(salad.selection.total == 8)
        #expect(soup.selection.isSelected(group: "size", value: "regular"))
        #expect(salad.selection.isSelected(group: "size", value: "regular"))

        soup.toggle(value: "herbs")
        soup.toggle(value: "croutons")
        soup.select(group: "size", value: "large")
        #expect(soup.selection.isToggled(value: "herbs"))
        #expect(soup.selection.isToggled(value: "croutons"))
        #expect(soup.selection.total == 8)
        #expect(soup.selection.selectionSummary == "Large soup, Extra herbs, Croutons")
        #expect(!salad.selection.isToggled(value: "croutons"))
        #expect(salad.selection.total == 8)
        #expect(!root.selection.isToggled(value: "herbs"))
        #expect(root.selection.total == 7)

        // Root interactions continue to work while sharing names with pages.
        root.select(group: "meal", value: "salad")
        #expect(root.selection.total == 9)
        #expect(soup.selection.total == 8)
        root.presentPage(titled: "Soup")
        root.dismissPresentedPage()
        root.presentPage(titled: "Soup")
        let reopened = root.pageSession(for: try #require(root.presentedPage?.page))
        #expect(reopened === soup)
        #expect(reopened.selection.isToggled(value: "herbs"))
        #expect(reopened.selection.isSelected(group: "size", value: "large"))
        let expectedTotal = soup.selection.formattedTotal(locale: Locale.current)
        #expect(soup.interpolated(.nav(brief: "Order {selections}: {total}")) ==
            .nav(brief: "Order Large soup, Extra herbs, Croutons: \(expectedTotal)"))
        salad.toggle(value: "croutons")
        soup.toggle(value: "croutons")
        #expect(salad.selection.isToggled(value: "croutons"))
        #expect(!soup.selection.isToggled(value: "croutons"))
    }

    @Test("An open detail page keeps edits while its content and resources stream")
    func pageStateDuringStreaming() async throws {
        guard #available(iOS 17.0, macOS 14.0, *) else { return }
        var continuation: AsyncThrowingStream<AuriUIStreamEvent, Error>.Continuation?
        let services = AuriUIHostServices(stream: { _ in
            AsyncThrowingStream { continuation = $0 }
        })
        let root = AuriUIScreenSession(brief: "Lunch", services: services)
        defer { root.cancel(); continuation?.finish() }
        root.start()
        try await waitForPage { continuation != nil }
        continuation?.yield(.delta(Self.lunch + "\n"))
        try await waitForPage { root.page(for: "Soup") != nil }
        let soup = root.pageSession(for: try #require(root.page(for: "Soup")))
        soup.toggle(value: "herbs")
        soup.select(group: "size", value: "large")
        let resource = URL(string: "https://example.com/recipe")!
        continuation?.yield(.resources(["r1": resource]))
        continuation?.yield(.document(text: Self.lunch.replacingOccurrences(of: "Fresh finish", with: "Updated herbs"), screenID: nil))
        try await waitForPage { root.phase == .ready }

        #expect(root.pageSession(for: try #require(root.page(for: "Soup"))) === soup)
        #expect(soup.selection.isToggled(value: "herbs"))
        #expect(soup.selection.isSelected(group: "size", value: "large"))
        #expect(soup.selection.total == 8)
        #expect(soup.resolveURL(.resource(id: "r1")) == resource)
        guard case .list(let options) = soup.document.sections.last else {
            Issue.record("Expected the final page options")
            return
        }
        #expect(options.items.first?.subtitle == "Updated herbs")
    }

    private static let lunch = """
    aui 1
    state base:1 cur:USD
    grid "Lunch"
    item 🍲 "Soup" "$6"
    item 🥗 "Salad" "$8"
    list "Root meal" pick:meal
    item 🍲 "Soup" val:soup price:6 sel
    item 🥗 "Salad" val:salad price:8
    page "Soup"
    state base:6 cur:USD
    list "Size" pick:size
    item 🥣 "Regular soup" val:regular price:0 sel
    item 🍜 "Large soup" val:large price:2
    list "Free options" multi
    item 🌿 "Extra herbs" "Fresh finish" val:herbs price:0
    item 🍞 "Croutons" "Crispy and golden" val:croutons price:0
    page "Salad"
    state base:8 cur:USD
    list "Size" pick:size
    item 🥗 "Regular salad" val:regular price:0 sel
    item 🥬 "Large salad" val:large price:3
    list "Free options" multi
    item 🍞 "Croutons" "Crispy and golden" val:croutons price:0
    """
}

@MainActor
private func waitForPage(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "Timed out waiting for page state")
}
#endif
