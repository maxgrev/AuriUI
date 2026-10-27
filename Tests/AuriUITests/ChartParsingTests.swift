//
//  ChartParsingTests.swift
//  AuriUITests
//
//  Charts are useful only when their numeric shape survives the model stream
//  intact. These tests keep the parser bounded, rectangular, and stable.
//

import Foundation
import Testing
@testable import AuriUI

@Suite("Chart parsing")
struct ChartParsingTests {

    @Test("A grounded multi-series line chart preserves order and values")
    func parsesLineChart() throws {
        let document = AuriUIStreamingParser.parse("""
        chart line "Weekly focus" unit:"min"
        point "Mon" "Focus" v:42
        point "Mon" "Meetings" v:18
        point "Tue" "Focus" v:55
        point "Tue" "Meetings" v:21
        """)

        let chart = try #require(document.charts.first)
        #expect(chart.kind == .line)
        #expect(chart.title == "Weekly focus")
        #expect(chart.unit == "min")
        #expect(chart.xLabels == ["Mon", "Tue"])
        #expect(chart.seriesNames == ["Focus", "Meetings"])
        #expect(chart.point(xLabel: "Tue", series: "Focus")?.value == 55)
        #expect(chart.isComplete)
    }

    @Test("Grouped bars support negative grounded values and a zero baseline")
    func parsesBarChart() throws {
        let document = AuriUIStreamingParser.parse("""
        chart bar "Monthly cash flow" unit:"USD"
        point "Jan" "Net" v:-120
        point "Feb" "Net" v:340
        """)

        let chart = try #require(document.charts.first)
        #expect(chart.kind == .bar)
        #expect(chart.points.map(\.value) == [-120, 340])
        #expect(chart.isComplete)
    }

    @Test("An open chart can stream progressively but cannot finish incomplete")
    func incompleteChartNeverFinalizes() throws {
        var parser = AuriUIStreamingParser()
        parser.consume("chart line \"Weekly focus\" unit:\"min\"\n")
        parser.consume("point \"Mon\" \"Focus\" v:42\n")

        let streamedChart = try #require(parser.document.charts.first)
        #expect(!streamedChart.isComplete)

        parser.finish()
        #expect(parser.document.charts.isEmpty)
    }

    @Test("Missing X/series pairs drop the entire completed chart")
    func rejectsNonRectangularChart() {
        let document = AuriUIStreamingParser.parse("""
        chart line "Weekly focus" unit:"min"
        point "Mon" "Focus" v:42
        point "Mon" "Meetings" v:18
        point "Tue" "Focus" v:55
        """)

        #expect(document.charts.isEmpty)
    }

    @Test("Invalid points drop by line without spoiling valid chart data")
    func dropsInvalidPoints() throws {
        var parser = AuriUIStreamingParser()
        parser.consume("""
        chart bar "Weekly orders" unit:"orders"
        point "Mon" "Orders" v:42
        point "Tue" "Orders" v:55
        point "Tue" "Orders" v:56
        point "Wed" "Orders" v:1000000000000001
        """)
        parser.finish()

        let chart = try #require(parser.document.charts.first)
        #expect(chart.points.count == 2)
        #expect(parser.droppedLineCount == 2)
    }

    @Test("Chart magnitude limits are inclusive and reject values beyond either bound")
    func enforcesMagnitudeBounds() throws {
        var parser = AuriUIStreamingParser()
        parser.consume("""
        chart bar "Magnitude bounds" unit:"units"
        point "Maximum" "Value" v:1000000000000000
        point "Minimum" "Value" v:-1000000000000000
        point "Too high" "Value" v:1000000000000001
        point "Too low" "Value" v:-1000000000000001
        """)
        parser.finish()

        let chart = try #require(parser.document.charts.first)
        let limit = try #require(Decimal(string: "1000000000000000", locale: Locale(identifier: "en_US_POSIX")))
        #expect(chart.points.map(\.value) == [limit, -limit])
        #expect(chart.isComplete)
        #expect(parser.droppedLineCount == 2)
    }

    @Test("Chart identity is stable across arbitrary stream boundaries")
    func stableAcrossChunks() {
        let text = """
        chart line "Weekly focus" unit:"min"
        point "Mon" "Focus" v:42
        point "Tue" "Focus" v:55
        """
        let reference = AuriUIStreamingParser.parse(text)

        var parser = AuriUIStreamingParser()
        for chunk in splitIntoChunks(text, size: 3) {
            parser.consume(chunk)
        }
        parser.finish()

        #expect(parser.document == reference)
    }
}
