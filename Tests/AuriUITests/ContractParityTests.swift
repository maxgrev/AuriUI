//
//  ContractParityTests.swift
//  AuriUITests
//
//  The generated contract is the shared vocabulary for the Swift parser,
//  Worker prompt, validator, and app capability advertisement.
//

import Testing
@testable import AuriUI

@Suite("Executable grammar contract")
struct ContractParityTests {

    @Test(
        "Every manifest component parses as its matching Swift section",
        arguments: AuriUIContract.components
    )
    func componentParity(component: AuriUIContract.Component) throws {
        var parser = AuriUIStreamingParser()
        parser.consume("aui 1\n\(component.sample)")
        parser.finish()

        #expect(parser.droppedLineCount == 0)
        #expect(parser.document.sections.count == 1)
        let section = try #require(parser.document.sections.first)
        #expect(section.contractComponentID == component.id)
    }

    @Test("Advertised components are supported members of the contract")
    func advertisedComponentsAreKnown() {
        #expect(Set(AuriUIContract.advertisedComponentIDs).isSubset(of: Set(AuriUIContract.componentIDs)))
        #expect(AuriUIContract.advertisedComponentIDs == ["chart", "table", "form"])
    }
}
