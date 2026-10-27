import AuriUI
import Testing

@Suite("Detail page money")
struct PageMoneyTests {
    @Test("Page state does not overwrite the root or another page, including during streaming")
    func scopedMoney() throws {
        var parser = AuriUIStreamingParser()
        parser.consume("""
        aui 1
        state base:1 cur:EUR
        grid "Lunch"
        item "Soup"
        item "Salad"
        item "Inherited"
        page "soup"
        state base:6
        intro "Soup"

        """)
        #expect(parser.document.money.base == 1)
        #expect(parser.document.pages.first?.money?.base == 6)
        #expect(parser.document.pages.first?.money?.currencyCode == "EUR")
        parser.consume("""
        page "Salad"
        state base:8 cur:USD
        intro "Salad"
        page "Inherited"
        intro "Uses root context"
        """)
        parser.finish()
        #expect(parser.document.money.base == 1)
        #expect(parser.document.money.currencyCode == "EUR")
        #expect(parser.document.pages.map(\.forTitle) == ["Soup", "Salad", "Inherited"])
        #expect(parser.document.pages[0].money?.base == 6)
        #expect(parser.document.pages[0].money?.currencyCode == "EUR")
        #expect(parser.document.pages[1].money?.base == 8)
        #expect(parser.document.pages[1].money?.currencyCode == "USD")
        #expect(parser.document.pages[2].money == nil)
    }
}
