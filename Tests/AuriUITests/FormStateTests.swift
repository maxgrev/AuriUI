//
//  FormStateTests.swift
//  AuriUITests
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Capability-gated forms")
struct FormStateTests {

    @Test("The parser accepts safe fields and a matching capability action")
    func parsesForm() throws {
        let document = AuriUIStreamingParser.parse(Self.formText)
        guard case .form(let form)? = document.sections.first else {
            Issue.record("Expected one parsed form")
            return
        }

        #expect(form.id == "refine_search")
        #expect(form.capabilityID == "nav")
        #expect(form.fields.map(\.kind) == [.text, .select, .date, .slider])
        #expect(form.submit.action.capabilityID == "nav")
    }

    @Test("Validation is local, deterministic, and field-specific")
    func validatesLocally() throws {
        let form = try #require(AuriUIStreamingParser.parse(Self.formText).forms.first)
        var state = AuriUIFormState(form: form)

        #expect(state.validationIssue(for: "query") == .required)
        state["query"] = "a"
        #expect(state.validationIssue(for: "query") == .tooShort(minimum: 2))
        state["query"] = "quiet cafe"
        #expect(state.isValid)

        state["timeframe"] = "not_an_option"
        #expect(state.validationIssue(for: "timeframe") == .invalidSelection)
    }

    @Test("Submit interpolation uses reviewed display values")
    func interpolatesDisplayValues() throws {
        let form = try #require(AuriUIStreamingParser.parse(Self.formText).forms.first)
        var state = AuriUIFormState(form: form)
        state["query"] = "quiet cafe"
        state["timeframe"] = "week"
        state["radius"] = "10"

        let action = state.interpolated(form.submit.action)
        #expect(action == .nav(brief: "Results for quiet cafe from Past week after 2026-07-31 within 10 mi"))
        #expect(state.reviewSummary.contains("Time frame: Past week"))
        #expect(state.reviewSummary.contains("Radius: 10 mi"))

        state["query"] = "{timeframe}"
        #expect(state.interpolate("{query} | {timeframe}") == "{timeframe} | Past week")
    }

    @Test("Sensitive fields and mismatched submit actions cannot form a section")
    func rejectsUnsafeShapes() {
        let password = AuriUIStreamingParser.parse("""
        form account "Account" cap:send
        field password secret "Password" required
        submit "Continue" @send("Use {secret}")
        """)
        let mismatch = AuriUIStreamingParser.parse("""
        form refine "Refine" cap:nav
        field text query "Query" required
        submit "Continue" @send("Use {query}")
        """)

        #expect(!password.isRenderable)
        #expect(!mismatch.isRenderable)
    }

    @Test("Date values reject impossible calendar days")
    func validatesDates() {
        #expect(AuriUIFormState.date(from: "2026-02-28") != nil)
        #expect(AuriUIFormState.date(from: "2026-02-30") == nil)
        #expect(AuriUIFormState.date(from: "not-a-date") == nil)
    }

    private static let formText = """
    aui 1
    form refine_search "Refine search" cap:nav confirm:"Search with these details?"
    field text query "Search terms" placeholder:"What are you looking for?" required min:2 max:80
    field select timeframe "Time frame" opt:"any=Any time" opt:"week=Past week" val:any
    field date after "After" val:2026-07-31
    field slider radius "Radius" min:1 max:100 step:1 val:25 unit:"mi"
    submit "Show results" @nav("Results for {query} from {timeframe} after {after} within {radius}")
    """
}
