import AuriUI
import Foundation
import Testing

@Suite("Public package integration")
struct PublicAPIIntegrationTests {
    @Test("A consumer can stream a document and act on local selections")
    func streamingAndSelection() throws {
        var parser = AuriUIStreamingParser()
        parser.consume("aui 1\nscreen lunch \"Lunch\"\nstate base:10 cur:USD\n")
        parser.consume("list \"Extras\" multi\nitem 🧀 \"Cheese\" val:cheese price:1.25\n")
        parser.consume("button primary \"Order {total}\" @send(\"Order with {total}\")")
        parser.finish()

        #expect(parser.failure == nil)
        #expect(parser.document.screen?.title == "Lunch")
        #expect(parser.document.isRenderable)
        guard case .list(let list)? = parser.document.sections.first else {
            Issue.record("Expected an option list")
            return
        }
        var state = AuriUISelectionState(document: parser.document)
        state.toggle(value: list.items[0].selectionValue)
        #expect(state.total == Decimal(string: "11.25"))
        #expect(state.interpolate("Order {total}", locale: Locale(identifier: "en_US")) == "Order $11.25")
    }

    @Test("Headerless input and recoverable malformed lines remain supported")
    func malformedContentRecovery() {
        var parser = AuriUIStreamingParser()
        parser.consume("intro \"Before\"\nintro \"unfinished\n")
        parser.consume("unknown \"Ignored\"\nintro \"After\"\n")
        parser.finish()

        #expect(parser.failure == nil)
        #expect(parser.droppedLineCount == 2)
        #expect(parser.document.sections == [.intro(text: "Before"), .intro(text: "After")])
    }

    @Test("Unknown versions reject the entire stream at every chunk boundary", arguments: [1, 3, 16])
    func unsupportedVersion(chunkSize: Int) {
        let text = "# Version gate\naui 2\nscreen ignored \"Ignored\"\nintro \"Never render\"\n"
        var parser = AuriUIStreamingParser()
        var remaining = text[...]
        while !remaining.isEmpty {
            let count = min(chunkSize, remaining.count)
            parser.consume(String(remaining.prefix(count)))
            remaining = remaining.dropFirst(count)
        }
        parser.finish()

        #expect(parser.failure == .unsupportedVersion(2))
        #expect(parser.document == AuriUIDocument())
        let changedAfterFailure = parser.consume("aui 1\nintro \"Cannot recover\"\n")
        #expect(!changedAfterFailure)
        #expect(AuriUIStreamingParser.parse(text) == AuriUIDocument())
    }

    @Test("Invalid version headers cannot fall through to v1 content", arguments: [
        "aui", "aui next", "aui 1 2", "aui \"1\"", "aui \"unterminated", "aui 1 extra:value",
    ])
    func invalidVersion(header: String) {
        var parser = AuriUIStreamingParser()
        parser.consume("\(header)\nintro \"Never render\"")
        parser.finish()
        #expect(parser.failure == .invalidVersionHeader)
        #expect(!parser.document.isRenderable)
    }

    @Test("A late version declaration clears already streamed content")
    func lateVersion() {
        var parser = AuriUIStreamingParser()
        parser.consume("intro \"Provisional\"\n")
        #expect(parser.document.isRenderable)
        let changedAfterHeader = parser.consume("aui 2\n")
        #expect(changedAfterHeader)
        parser.finish()
        #expect(parser.failure == .misplacedVersionHeader)
        #expect(parser.document == AuriUIDocument())
    }

    @Test("Publicly constructed forms use the first field for a repeated ID")
    func duplicateFieldIDs() {
        let first = AuriUIFormField(id: "query", kind: .text, label: "Query", isRequired: true)
        let duplicate = AuriUIFormField(id: "query", kind: .text, label: "Duplicate", initialValue: "Wrong")
        var form = AuriUIForm(
            id: "search",
            title: "Search",
            capabilityID: "send",
            fields: [first, duplicate],
            submit: .init(label: "Search", action: .send(prompt: "Find {query}"))
        )
        #expect(form.fields == [first])
        form.fields.append(duplicate)
        #expect(form.fields == [first])

        var state = AuriUIFormState(form: form)
        #expect(state.validationIssues == ["query": .required])
        #expect(!state.isValid)
        state["query"] = "Coffee"
        #expect(state.isValid)
        #expect(state.reviewSummary == "Query: Coffee")
        #expect(state.interpolated(form.submit.action) == .send(prompt: "Find Coffee"))
    }
}
