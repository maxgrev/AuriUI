import AuriUI
import Foundation
import Testing

@Suite("Legacy document consumer compatibility")
struct LegacyDocumentTests {
    @Test("Public constructors match persisted legacy document decoding")
    func publicConstructionAndDecoding() throws {
        // Use a normal import, not @testable: the renderer is a separate module
        // and must be able to construct every adapter model through public API.
        let expected = ChatVisualDocument(summary: "Legacy answer", sections: [
            ChatVisualSection(id: "s0", kind: .mediaRow(items: [
                VisualItem(title: "Alpha", subtitle: "First item"),
            ])),
            ChatVisualSection(id: "s1", kind: .entityCards(cards: [
                VisualCard(title: "Beta", stats: [VisualStat(label: "Pages", value: "12")]),
            ])),
            ChatVisualSection(id: "s2", kind: .comparison(
                columns: [VisualColumn(title: "Alpha"), VisualColumn(title: "Beta")],
                groups: [VisualComparisonGroup(title: "Details", rows: [
                    VisualComparisonRow(label: "Size", values: [
                        VisualComparisonValue(text: "Small", verdict: .good, note: "Fits"),
                        VisualComparisonValue(text: "Large"),
                    ]),
                ])]
            )),
            ChatVisualSection(id: "s3", kind: .tabs(tabs: [
                VisualTab(title: "Overview", sections: [
                    ChatVisualSection(id: "s3-t0-0", kind: .intro(text: "Saved content")),
                ]),
            ])),
        ])
        let json = #"""
        {
          "summary": "Legacy answer",
          "sections": [
            {"type":"media_row","items":[{"title":"Alpha","subtitle":"First item"}]},
            {"type":"entity_cards","cards":[{"title":"Beta","stats":[{"label":"Pages","value":"12"}]}]},
            {"type":"comparison","columns":[{"title":"Alpha"},{"title":"Beta"}],"groups":[
              {"title":"Details","rows":[{"label":"Size","values":[
                {"text":"Small","verdict":"good","note":"Fits"},
                {"text":"Large","verdict":"unknown"}
              ]}]}
            ]},
            {"type":"tabs","tabs":[{"title":"Overview","sections":[{"type":"intro","text":"Saved content"}]}]}
          ]
        }
        """#

        let decoded = try JSONDecoder().decode(ChatVisualDocument.self, from: Data(json.utf8))
        #expect(decoded == expected)
    }
}
