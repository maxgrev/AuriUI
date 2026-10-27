#if os(iOS) || os(macOS)
//
//  AuriUIChartView.swift
//  Auri
//
//  Native rendering for bounded AuriUI line and grouped-bar charts. FLChart
//  supplied the visual foundation; Auri adds contract-driven identity,
//  selection, truthful domains, and a table fallback from the same data.
//

import AuriUI
import Charts
import Foundation
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIChartView: View {
    let chart: AuriUIChart

    @State private var selectedXLabel: String?
    @State private var isShowingData = false

    @ScaledMetric(relativeTo: .body) private var chartHeight = 210.0
    @ScaledMetric(relativeTo: .caption) private var pointWidth = 56.0

    private let model: AuriUIChartPlotModel
    private let valueFormatter: AuriUIChartValueFormatter

    public init(
        chart: AuriUIChart,
        initiallyShowsData: Bool = false,
        initiallySelectedXLabel: String? = nil,
        plotHeight: Double = 210
    ) {
        self.chart = chart
        self.model = AuriUIChartPlotModel(chart: chart)
        self.valueFormatter = AuriUIChartValueFormatter(unit: chart.unit)
        _isShowingData = State(initialValue: initiallyShowsData)
        _selectedXLabel = State(initialValue: initiallySelectedXLabel)
        _chartHeight = ScaledMetric(wrappedValue: plotHeight, relativeTo: .body)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VisualSectionTitle(title: chart.title)
                Spacer(minLength: 8)
                Text(chart.unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                plot
                    .accessibilityIdentifier("auri.ui.chart.\(chart.title)")

                if chart.isComplete {
                    AuriUIChartSelectionView(
                        selectedXLabel: selectedXLabel,
                        model: model,
                        valueFormatter: valueFormatter
                    )

                    Divider()

                    DisclosureGroup(isExpanded: $isShowingData) {
                        AuriUIChartDataTableView(
                            model: model,
                            valueFormatter: valueFormatter
                        )
                        .padding(.top, 10)
                    } label: {
                        Label("View data", systemImage: "tablecells")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(Color.primary)
                    .accessibilityIdentifier("auri.ui.chart.data.\(chart.title)")
                } else {
                    Label("Building chart…", systemImage: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Chart data is still loading"))
                }
            }
            .padding(14)
            .visualCard(treatment: .grouped)
        }
        .sensoryFeedback(.selection, trigger: selectedXLabel)
        .onChange(of: model.xLabels) {
            guard let selectedXLabel,
                  !model.xLabels.contains(selectedXLabel) else {
                return
            }
            self.selectedXLabel = nil
        }
    }

    @ViewBuilder
    private var plot: some View {
        let height = min(chartHeight, 300)
        if model.xLabels.count > 6 {
            let minimumWidth = min(pointWidth, 72) * Double(model.xLabels.count)
            ScrollView(.horizontal) {
                AuriUIChartPlot(
                    chart: chart,
                    model: model,
                    selectedXLabel: $selectedXLabel
                )
                .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                    max(length, minimumWidth)
                }
                .frame(height: height)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        } else {
            AuriUIChartPlot(
                chart: chart,
                model: model,
                selectedXLabel: $selectedXLabel
            )
            .frame(height: height)
        }
    }
}



@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIChartPlot: View {
    let chart: AuriUIChart
    let model: AuriUIChartPlotModel
    @Binding var selectedXLabel: String?

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        Chart {
            ForEach(model.points) { point in
                if chart.kind == .line {
                    LineMark(
                        x: .value("Period", point.xLabel),
                        y: .value(chart.unit, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Period", point.xLabel),
                        y: .value(chart.unit, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbol(by: .value("Series", point.series))
                    .symbolSize(28)
                } else {
                    BarMark(
                        x: .value("Category", point.xLabel),
                        y: .value(chart.unit, point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            if let selectedXLabel {
                RuleMark(x: .value("Selected", selectedXLabel))
                    .foregroundStyle(accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if model.crossesZero {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: model.xLabels)
        .chartYScale(domain: model.yDomain)
        .chartXAxis {
            AxisMarks(values: model.xLabels) {
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                    .foregroundStyle(.secondary.opacity(0.35))
                AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                    .foregroundStyle(.secondary.opacity(0.18))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(AuriUIChartValueFormatter.compactNumber(number))
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartLegend(model.seriesNames.count > 1 ? .visible : .hidden)
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .chartXSelection(value: $selectedXLabel)
        .accessibilityLabel(Text(chart.title))
        .accessibilityHint(Text("Explore the chart, or expand View data for a table"))
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIChartSelectionView: View {
    let selectedXLabel: String?
    let model: AuriUIChartPlotModel
    let valueFormatter: AuriUIChartValueFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let selectedXLabel {
                Text(selectedXLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(model.values(at: selectedXLabel)) { point in
                        GridRow {
                            Text(point.series)
                                .foregroundStyle(.secondary)
                            Text(valueFormatter.full(point.value))
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .font(.subheadline)
            } else {
                Text("Range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(valueFormatter.range(model.minimumValue, model.maximumValue))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIChartDataTableView: View {
    let model: AuriUIChartPlotModel
    let valueFormatter: AuriUIChartValueFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.xLabels, id: \.self) { xLabel in
                VStack(alignment: .leading, spacing: 6) {
                    Text(xLabel)
                        .font(.subheadline.weight(.semibold))

                    ForEach(model.values(at: xLabel)) { point in
                        Text("\(point.series): \(valueFormatter.full(point.value))")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(model.accessibilityRow(
                    xLabel: xLabel,
                    valueFormatter: valueFormatter
                )))

                if xLabel != model.xLabels.last {
                    Divider()
                }
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIChartPlotModel: Equatable {
    struct Point: Identifiable, Equatable {
        let id: String
        let xLabel: String
        let series: String
        let value: Double
    }

    private struct Coordinate: Hashable {
        let xLabel: String
        let series: String
    }

    let points: [Point]
    let xLabels: [String]
    let seriesNames: [String]
    let minimumValue: Double
    let maximumValue: Double
    let yDomain: ClosedRange<Double>
    let crossesZero: Bool
    private let pointsByCoordinate: [Coordinate: Point]

    init(chart: AuriUIChart) {
        let points = chart.points.map { point in
            Point(
                id: point.id,
                xLabel: point.xLabel,
                series: point.series,
                value: NSDecimalNumber(decimal: point.value).doubleValue
            )
        }
        let values = points.map(\.value)
        let minimumValue = values.min() ?? 0
        let maximumValue = values.max() ?? 0

        self.points = points
        self.xLabels = chart.xLabels
        self.seriesNames = chart.seriesNames
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.yDomain = Self.domain(
            kind: chart.kind,
            minimum: minimumValue,
            maximum: maximumValue
        )
        self.crossesZero = minimumValue < 0 && maximumValue > 0
        self.pointsByCoordinate = Dictionary(uniqueKeysWithValues: points.map {
            (Coordinate(xLabel: $0.xLabel, series: $0.series), $0)
        })
    }

    func values(at xLabel: String) -> [Point] {
        seriesNames.compactMap { series in
            pointsByCoordinate[Coordinate(xLabel: xLabel, series: series)]
        }
    }

    func accessibilityRow(
        xLabel: String,
        valueFormatter: AuriUIChartValueFormatter
    ) -> String {
        let values = values(at: xLabel).map {
            "\($0.series), \(valueFormatter.full($0.value))"
        }
        return ([xLabel] + values).joined(separator: ", ")
    }

    private static func domain(
        kind: AuriUIChart.Kind,
        minimum: Double,
        maximum: Double
    ) -> ClosedRange<Double> {
        if minimum == maximum {
            if kind == .bar {
                if maximum > 0 { return 0...(maximum * 1.1) }
                if minimum < 0 { return (minimum * 1.1)...0 }
                return 0...1
            }
            let padding = max(abs(minimum) * 0.1, 1)
            return (minimum - padding)...(maximum + padding)
        }

        if kind == .bar {
            let lower = min(0, minimum)
            let upper = max(0, maximum)
            let padding = max((upper - lower) * 0.08, 0.01)
            return (lower < 0 ? lower - padding : 0)...(upper > 0 ? upper + padding : 0)
        }

        let padding = max((maximum - minimum) * 0.08, 0.01)
        return (minimum - padding)...(maximum + padding)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIChartValueFormatter: Equatable {
    let unit: String

    func full(_ value: Double) -> String {
        attachUnit(to: value.formatted(
            .number.precision(.fractionLength(0...2))
        ))
    }

    func range(_ lower: Double, _ upper: Double) -> String {
        if lower == upper { return full(lower) }
        return "\(full(lower))–\(full(upper))"
    }

    static func compactNumber(_ value: Double) -> String {
        value.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
    }

    private func attachUnit(to number: String) -> String {
        let joinsDirectly = unit.hasPrefix("%") || unit.hasPrefix("°")
        return "\(number)\(joinsDirectly ? "" : " ")\(unit)"
    }
}
#endif
