import Foundation
import Testing
@testable import AuriUI
@testable import AuriUIDemo

@Suite("Standalone demo resources")
struct DemoFixtureTests {
    @Test("Bundled samples parse cleanly and cover the full component catalog")
    func samplesCoverContract() throws {
        var components = Set<String>()
        for sample in DemoSample.gallery + DemoSample.interactive where sample.id != "host" {
            var parser = AuriUIStreamingParser()
            parser.consume(try DemoResources.text(sample.id))
            parser.finish()
            #expect(parser.failure == nil, "Invalid version in \(sample.id)")
            #expect(parser.droppedLineCount == 0, "Malformed line in \(sample.id)")
            #expect(parser.document.isRenderable, "Empty sample \(sample.id)")
            components.formUnion(parser.document.sections.map(\.contractComponentID))
        }
        #expect(components == Set(AuriUIContract.componentIDs))
    }

    @Test("Detail page and image resources survive standalone app packaging")
    func bundledDetailAndImages() throws {
        let document = AuriUIStreamingParser.parse(try DemoResources.text("media"))
        #expect(document.pages.map(\.forTitle) == ["Hill walk", "Soup", "Salad"])
        #expect(document.pages.first?.forTitle == "Hill walk")
        for name in ["hills", "cover"] {
            let url = try #require(DemoResources.imageURL(name))
            #expect(url.isFileURL)
            #expect(try Data(contentsOf: url).count > 100)
        }
    }

    @Test("The streaming sample produces the same document in small chunks")
    func streamedSample() throws {
        let text = try DemoResources.text("stream")
        let complete = AuriUIStreamingParser.parse(text)
        var parser = AuriUIStreamingParser()
        for character in text {
            parser.consume(String(character))
        }
        parser.finish()
        #expect(parser.document == complete)
        #expect(parser.droppedLineCount == 0)
        #expect(complete.sections.count == 4)
    }
}
