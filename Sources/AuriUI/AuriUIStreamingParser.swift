//
//  AuriUIStreamingParser.swift
//  AuriUI
//
//  Incremental, lossy parser for AuriUI v1. Feed it raw model output in
//  arbitrary chunks; every completed line updates `document` immediately, so
//  the client renders while tokens stream. Malformed lines are dropped
//  individually — one bad ingredient never takes the screen down (the same
//  philosophy as the v1 JSON sanitizer).
//

import Foundation

/// A version declaration that prevents this parser from safely interpreting
/// the document. Ordinary malformed content still drops one line at a time.
public enum AuriUIParsingFailure: LocalizedError, Equatable, Sendable {
    case invalidVersionHeader
    case unsupportedVersion(Int)
    case misplacedVersionHeader

    public var errorDescription: String? {
        switch self {
        case .invalidVersionHeader:
            return "The AuriUI version header is invalid. Expected aui \(AuriUIContract.version)."
        case .unsupportedVersion(let version):
            return "AuriUI version \(version) is not supported. This client supports version \(AuriUIContract.version)."
        case .misplacedVersionHeader:
            return "The AuriUI version header must appear before document content and only once."
        }
    }
}

public struct AuriUIStreamingParser: Sendable {

    /// The best current snapshot, updated after every completed line. The
    /// open container's items are included, so tiles appear one by one.
    /// Sections inside an unfinished `tabs` block land when the block closes.
    public private(set) var document = AuriUIDocument()

    /// Lines that were lexically or semantically unusable (telemetry).
    public private(set) var droppedLineCount = 0

    /// A fatal version error. Once set, `document` is empty and further chunks
    /// are ignored. Create a new parser to begin another document.
    public private(set) var failure: AuriUIParsingFailure?

    public init() {}

    /// Parses a complete document in one call. Invalid or unsupported version
    /// declarations produce an empty document. Use a parser instance to read
    /// the specific `failure`.
    public static func parse(_ text: String) -> AuriUIDocument {
        var parser = AuriUIStreamingParser()
        parser.consume(text)
        parser.finish()
        return parser.document
    }

    /// Feeds a chunk of streamed text. Returns true when `document` changed.
    @discardableResult
    public mutating func consume(_ chunk: String) -> Bool {
        guard !finished, failure == nil else { return false }
        let before = document
        lineBuffer += chunk
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
            processLine(line)
        }
        rebuildDocument()
        return document != before
    }

    /// Flushes the trailing unterminated line, closes open blocks, and
    /// reconciles detail pages against tile titles. Idempotent.
    @discardableResult
    public mutating func finish() -> Bool {
        guard !finished else { return false }
        finished = true
        let before = document
        if !lineBuffer.isEmpty {
            processLine(lineBuffer)
            lineBuffer = ""
        }
        closeContainer()
        closeTabs()
        closePage()
        reconcilePages()
        rebuildDocument()
        return document != before
    }

    // MARK: - Internal state

    private var finished = false
    private var hasContentLine = false
    private var lineBuffer = ""

    private var screenHeader: AuriUIScreenHeader?
    private var summary: String?
    private var money = AuriUIMoneyContext()
    private var topSections: [AuriUISection] = []
    private var completedPages: [AuriUIPage] = []
    private var currentPage: (title: String, sections: [AuriUISection], money: AuriUIMoneyContext?)?

    private var inTabs = false
    private var completedTabs: [AuriUITab] = []
    private var currentTab: (title: String, sections: [AuriUISection])?

    private var open: OpenContainer?
    private var formIDs: Set<String> = []

    private enum OpenContainer {
        case row(title: String?, items: [AuriUITile])
        case posters(title: String?, items: [AuriUITile])
        case menu(title: String?, items: [AuriUIMenuItem])
        case grid(title: String?, items: [AuriUITile])
        case cards([AuriUICard])
        case steps(title: String?, items: [AuriUIStep])
        case facts(title: String?, items: [AuriUIStep])
        case bullets(title: String?, checklist: Bool, items: [String])
        case stats(title: String?, items: [AuriUIStat])
        case expand(title: String?, items: [AuriUIExpandable])
        case chips([AuriUIChip])
        case sources([AuriUISource])
        case list(title: String?, mode: AuriUIOptionList.Mode, items: [AuriUIOption])
        case receipt(title: String?, lines: [AuriUIReceiptLine])
        case compare(
            emoji: String?,
            columns: [AuriUIComparison.Column],
            groups: [AuriUIComparison.Group],
            groupTitle: String?,
            rows: [AuriUIComparison.Row]
        )
        case chart(kind: AuriUIChart.Kind, title: String, unit: String, points: [AuriUIChart.Point])
        case table(title: String?, columns: [AuriUITable.Column], rows: [AuriUITable.Row])
        case form(
            id: String,
            title: String,
            capabilityID: String,
            confirmation: String?,
            fields: [AuriUIFormField],
            submit: AuriUIFormSubmit?
        )
    }

    // MARK: - Line processing

    private mutating func processLine(_ raw: String) {
        guard failure == nil else { return }
        switch AuriUILexer.tokenize(raw) {
        case .ignored:
            return
        case .malformed:
            hasContentLine = true
            if raw.split(whereSeparator: \.isWhitespace).first?.lowercased() == "aui" {
                failure = .invalidVersionHeader
            }
            droppedLineCount += 1
        case .line(let line):
            defer { hasContentLine = true }
            if !apply(line) {
                droppedLineCount += 1
            }
        }
    }

    /// Applies one lexed line. Returns false when the line had to be dropped.
    private mutating func apply(_ line: AuriUILexedLine) -> Bool {
        switch line.keyword {
        case "aui":
            guard !hasContentLine else {
                failure = .misplacedVersionHeader
                return false
            }
            guard line.flags.count == 1,
                  let version = Int(line.flags[0]),
                  line.strings.isEmpty, line.pairs.isEmpty,
                  line.emoji == nil, line.action == nil else {
                failure = .invalidVersionHeader
                return false
            }
            guard version == AuriUIContract.version else {
                failure = .unsupportedVersion(version)
                return false
            }
            return true

        case "screen":
            guard screenHeader == nil, topSections.isEmpty,
                  let id = line.flags.first, let title = line.strings.first else { return false }
            screenHeader = AuriUIScreenHeader(
                id: id,
                title: title,
                subtitle: line.strings.count > 1 ? line.strings[1] : nil,
                tint: line.pair("tint").flatMap { $0.isEmpty ? nil : $0.lowercased() }
            )
            return true

        case "summary":
            guard summary == nil, let text = line.strings.first, !text.isEmpty else { return false }
            summary = text
            return true

        case "state":
            var context = currentPage?.money ?? money
            if let base = line.pair("base"), let value = Self.decimal(base) {
                context.base = value
            }
            if let currency = line.pair("cur"), !currency.isEmpty {
                context.currencyCode = currency.uppercased()
            }
            if currentPage != nil { currentPage?.money = context }
            else { money = context }
            return true

        case "intro":
            guard let text = line.strings.first, !text.isEmpty else { return false }
            return appendSection(.intro(text: text))

        case "header":
            guard let title = line.strings.first, !title.isEmpty else { return false }
            return appendSection(.header(
                emoji: line.emoji,
                title: title,
                subtitle: line.strings.count > 1 ? line.strings[1] : nil
            ))

        case "hero":
            let imageQuery = line.pair("img")
            let caption = line.strings.first
            guard imageQuery != nil || caption != nil else { return false }
            return appendSection(.hero(imageQuery: imageQuery, caption: caption))

        case "button":
            guard let label = line.strings.first, !label.isEmpty else { return false }
            return appendSection(.button(AuriUIButton(
                label: label,
                isPrimary: line.hasFlag("primary"),
                action: line.action
            )))

        case "row":
            openContainer(.row(title: line.strings.first, items: []))
            return true
        case "posters":
            openContainer(.posters(title: line.strings.first, items: []))
            return true
        case "menu":
            openContainer(.menu(title: line.strings.first, items: []))
            return true
        case "grid":
            openContainer(.grid(title: line.strings.first, items: []))
            return true
        case "cards":
            openContainer(.cards([]))
            return true
        case "steps":
            openContainer(.steps(title: line.strings.first, items: []))
            return true
        case "facts":
            openContainer(.facts(title: line.strings.first, items: []))
            return true
        case "bullets":
            openContainer(.bullets(title: line.strings.first, checklist: line.hasFlag("check"), items: []))
            return true
        case "stats":
            openContainer(.stats(title: line.strings.first, items: []))
            return true
        case "expand":
            openContainer(.expand(title: line.strings.first, items: []))
            return true
        case "chips":
            openContainer(.chips([]))
            return true
        case "sources":
            openContainer(.sources([]))
            return true
        case "receipt":
            openContainer(.receipt(title: line.strings.first, lines: []))
            return true

        case "list":
            let mode: AuriUIOptionList.Mode
            if let group = line.pair("pick"), !group.isEmpty {
                mode = .pick(group: group)
            } else {
                mode = .multi
            }
            openContainer(.list(title: line.strings.first, mode: mode, items: []))
            return true

        case "compare":
            // Columns come from positional titles here and/or `col` lines
            // (which can carry contender images) that follow.
            openContainer(.compare(
                emoji: line.emoji,
                columns: line.strings.prefix(3).map { AuriUIComparison.Column(title: $0) },
                groups: [],
                groupTitle: nil,
                rows: []
            ))
            return true

        case "chart":
            guard let rawKind = line.flags.first?.lowercased(),
                  let kind = AuriUIChart.Kind(rawValue: rawKind),
                  let rawTitle = line.strings.first,
                  let rawUnit = line.pair("unit") else {
                return false
            }
            let title = rawTitle.trimmingCharacters(in: .whitespaces)
            let unit = rawUnit.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, title.count <= 80,
                  !unit.isEmpty, unit.count <= 24 else {
                return false
            }
            openContainer(.chart(kind: kind, title: title, unit: unit, points: []))
            return true

        case "point":
            return appendChartPoint(line)

        case "table":
            openContainer(.table(title: line.strings.first, columns: [], rows: []))
            return true

        case "form":
            closeContainer()
            guard let id = line.flags.first,
                  Self.isIdentifier(id),
                  let title = line.strings.first,
                  !title.isEmpty,
                  let capabilityID = line.pair("cap")?.lowercased(),
                  capabilityID == "nav" || capabilityID == "send",
                  formIDs.insert(id).inserted else {
                return false
            }
            open = .form(
                id: id,
                title: title,
                capabilityID: capabilityID,
                confirmation: line.pair("confirm").flatMap { $0.isEmpty ? nil : $0 },
                fields: [],
                submit: nil
            )
            return true

        case "field":
            return appendFormField(line)

        case "submit":
            return appendFormSubmit(line)

        case "tcol":
            guard case .table(let title, var columns, let rows) = open,
                  rows.isEmpty, columns.count < 4,
                  let columnTitle = line.strings.first, !columnTitle.isEmpty else { return false }
            let id = line.pair("id").flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.stableID(columnTitle, ordinal: columns.count)
            columns.append(AuriUITable.Column(id: id, title: columnTitle))
            open = .table(title: title, columns: columns, rows: rows)
            return true

        case "trow":
            guard case .table(let title, let columns, var rows) = open,
                  (2...4).contains(columns.count), !line.strings.isEmpty else { return false }
            var values = line.strings
            while values.count < columns.count { values.append("") }
            values = Array(values.prefix(columns.count))
            let cells = zip(columns, values).map { column, value in
                AuriUITable.Cell(id: column.id, text: value)
            }
            let id = line.pair("id").flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.stableID(values.joined(separator: "|"), ordinal: rows.count)
            rows.append(AuriUITable.Row(id: id, cells: cells, isHighlighted: line.hasFlag("hi")))
            open = .table(title: title, columns: columns, rows: rows)
            return true

        case "col":
            guard case .compare(let emoji, var columns, let groups, let groupTitle, let rows) = open,
                  columns.count < 3, rows.isEmpty, groups.isEmpty,
                  let title = line.strings.first, !title.isEmpty else { return false }
            columns.append(AuriUIComparison.Column(title: title, imageQuery: line.pair("img")))
            open = .compare(emoji: emoji, columns: columns, groups: groups, groupTitle: groupTitle, rows: rows)
            return true

        case "cgroup":
            guard case .compare(let emoji, let columns, var groups, let groupTitle, let rows) = open else { return false }
            if !rows.isEmpty {
                groups.append(AuriUIComparison.Group(title: groupTitle, rows: rows))
            }
            open = .compare(
                emoji: emoji,
                columns: columns,
                groups: groups,
                groupTitle: line.strings.first,
                rows: []
            )
            return true

        case "crow":
            guard case .compare(let emoji, let columns, let groups, let groupTitle, var rows) = open,
                  columns.count >= 2,
                  let label = line.strings.first, line.strings.count >= 2 else { return false }
            var values = Array(line.strings.dropFirst())
            while values.count < columns.count { values.append("") }
            values = Array(values.prefix(columns.count))
            let winner = line.pair("win").flatMap { Int($0) }
            let notes = (1...columns.count).map { index in
                line.pair("n\(index)").flatMap { $0.isEmpty ? nil : $0 }
            }
            rows.append(AuriUIComparison.Row(
                label: label,
                values: values,
                winner: winner.flatMap { (1...columns.count).contains($0) ? $0 : nil },
                notes: notes
            ))
            open = .compare(emoji: emoji, columns: columns, groups: groups, groupTitle: groupTitle, rows: rows)
            return true

        case "tabs":
            // Tabs never nest and never appear inside pages.
            guard !inTabs, currentPage == nil else { return false }
            closeContainer()
            inTabs = true
            completedTabs = []
            currentTab = nil
            return true

        case "tab":
            guard inTabs, let title = line.strings.first, !title.isEmpty else { return false }
            closeContainer()
            flushCurrentTab()
            currentTab = (title: title, sections: [])
            return true

        case "end":
            guard inTabs else { return false }
            closeContainer()
            closeTabs()
            return true

        case "page":
            guard let title = line.strings.first, !title.isEmpty else { return false }
            closeContainer()
            closeTabs()
            closePage()
            currentPage = (title: title, sections: [], money: nil)
            return true

        case "item":
            return appendItem(line)

        default:
            return false
        }
    }

    // MARK: - Items

    private mutating func appendItem(_ line: AuriUILexedLine) -> Bool {
        guard let container = open else { return false }

        switch container {
        case .row(let title, var items):
            guard let tile = Self.tile(from: line) else { return false }
            items.append(tile)
            open = .row(title: title, items: items)

        case .posters(let title, var items):
            guard let tile = Self.tile(from: line) else { return false }
            items.append(tile)
            open = .posters(title: title, items: items)

        case .menu(let title, var items):
            guard let itemTitle = line.strings.first, !itemTitle.isEmpty else { return false }
            items.append(AuriUIMenuItem(
                emoji: line.emoji,
                title: itemTitle,
                detail: line.strings.count > 1 ? line.strings[1] : nil,
                price: line.pair("price").flatMap(Self.decimal),
                imageQuery: line.pair("img"),
                badge: line.pair("badge"),
                action: line.action
            ))
            open = .menu(title: title, items: items)

        case .grid(let title, var items):
            guard let tile = Self.tile(from: line) else { return false }
            items.append(tile)
            open = .grid(title: title, items: items)

        case .cards(var cards):
            guard let cardTitle = line.strings.first, !cardTitle.isEmpty else { return false }
            let stats = line.pairValues("s").compactMap { pair -> AuriUIStatPair? in
                guard let separator = pair.firstIndex(of: "=") else { return nil }
                let label = String(pair[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(pair[pair.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                guard !label.isEmpty, !value.isEmpty else { return nil }
                return AuriUIStatPair(label: label, value: value)
            }
            cards.append(AuriUICard(
                emoji: line.emoji,
                title: cardTitle,
                subtitle: line.strings.count > 1 ? line.strings[1] : nil,
                imageQuery: line.pair("img"),
                stats: Array(stats.prefix(3)),
                action: line.action
            ))
            open = .cards(cards)

        case .steps(let title, var items):
            guard let stepTitle = line.strings.first, !stepTitle.isEmpty else { return false }
            items.append(AuriUIStep(
                emoji: line.emoji,
                title: stepTitle,
                detail: line.strings.count > 1 ? line.strings[1] : nil
            ))
            open = .steps(title: title, items: items)

        case .facts(let title, var items):
            guard let factTitle = line.strings.first, !factTitle.isEmpty else { return false }
            items.append(AuriUIStep(
                emoji: line.emoji,
                title: factTitle,
                detail: line.strings.count > 1 ? line.strings[1] : nil
            ))
            open = .facts(title: title, items: items)

        case .bullets(let title, let checklist, var items):
            guard let text = line.strings.first, !text.isEmpty else { return false }
            items.append(text)
            open = .bullets(title: title, checklist: checklist, items: items)

        case .stats(let title, var items):
            guard let value = line.strings.first, !value.isEmpty else { return false }
            items.append(AuriUIStat(
                value: value,
                label: line.strings.count > 1 ? line.strings[1] : nil,
                trend: line.pair("trend").flatMap { AuriUIStat.Trend(rawValue: $0) }
            ))
            open = .stats(title: title, items: items)

        case .expand(let title, var items):
            guard line.strings.count >= 2 else { return false }
            items.append(AuriUIExpandable(title: line.strings[0], body: line.strings[1]))
            open = .expand(title: title, items: items)

        case .chips(var chips):
            guard let label = line.strings.first, !label.isEmpty else { return false }
            chips.append(AuriUIChip(
                label: label,
                prompt: line.strings.count > 1 ? line.strings[1] : label
            ))
            open = .chips(chips)

        case .sources(var sources):
            guard let urlString = line.pair("url"), !urlString.isEmpty else { return false }
            sources.append(AuriUISource(title: line.strings.first, urlString: urlString))
            open = .sources(sources)

        case .list(let title, let mode, var items):
            guard let optionTitle = line.strings.first, !optionTitle.isEmpty else { return false }
            let value = line.pair("val").flatMap { $0.isEmpty ? nil : $0 } ?? Self.slug(optionTitle)
            guard !value.isEmpty else { return false }
            items.append(AuriUIOption(
                emoji: line.emoji,
                title: optionTitle,
                subtitle: line.strings.count > 1 ? line.strings[1] : nil,
                selectionValue: value,
                price: line.pair("price").flatMap(Self.decimal) ?? 0,
                selectedByDefault: line.hasFlag("sel")
            ))
            open = .list(title: title, mode: mode, items: items)

        case .receipt(let title, var lines):
            guard let label = line.strings.first, !label.isEmpty else { return false }
            lines.append(AuriUIReceiptLine(
                label: label,
                price: line.pair("price").flatMap(Self.decimal) ?? 0
            ))
            open = .receipt(title: title, lines: lines)

        case .compare:
            return false

        case .chart:
            return false

        case .table:
            return false

        case .form:
            return false
        }

        return true
    }

    private mutating func appendChartPoint(_ line: AuriUILexedLine) -> Bool {
        guard case .chart(let kind, let title, let unit, var points) = open,
              points.count < AuriUIChart.maximumPointCount,
              line.strings.count == 2,
              let rawValue = line.pair("v"),
              let value = Self.decimal(rawValue),
              value >= -AuriUIChart.maximumMagnitude,
              value <= AuriUIChart.maximumMagnitude else {
            return false
        }

        let xLabel = line.strings[0].trimmingCharacters(in: .whitespaces)
        let series = line.strings[1].trimmingCharacters(in: .whitespaces)
        guard !xLabel.isEmpty, xLabel.count <= 32,
              !series.isEmpty, series.count <= 32,
              !points.contains(where: { $0.xLabel == xLabel && $0.series == series }) else {
            return false
        }

        let xLabels = Set(points.map(\.xLabel))
        let seriesNames = Set(points.map(\.series))
        guard xLabels.contains(xLabel) || xLabels.count < AuriUIChart.maximumXValueCount,
              seriesNames.contains(series) || seriesNames.count < AuriUIChart.maximumSeriesCount else {
            return false
        }

        points.append(AuriUIChart.Point(
            id: Self.stableID("\(xLabel)|\(series)", ordinal: points.count),
            xLabel: xLabel,
            series: series,
            value: value
        ))
        open = .chart(kind: kind, title: title, unit: unit, points: points)
        return true
    }

    private mutating func appendFormField(_ line: AuriUILexedLine) -> Bool {
        guard case .form(
            let formID,
            let title,
            let capabilityID,
            let confirmation,
            var fields,
            let submit
        ) = open,
        submit == nil,
        fields.count < 6,
        line.flags.count >= 2,
        let kind = AuriUIFormField.Kind(rawValue: line.flags[0].lowercased()),
        Self.isIdentifier(line.flags[1]),
        !fields.contains(where: { $0.id == line.flags[1] }),
        let label = line.strings.first,
        !label.isEmpty else {
            return false
        }

        let fieldID = line.flags[1]
        let initialValue = line.pair("val") ?? ""
        let field: AuriUIFormField

        switch kind {
        case .text, .textArea:
            let defaultMaximum = kind == .text ? 200 : 1_000
            let minimumLength = line.pair("min").flatMap(Int.init)
            let maximumLength = line.pair("max").flatMap(Int.init) ?? defaultMaximum
            guard maximumLength > 0,
                  maximumLength <= 2_000,
                  minimumLength.map({ $0 >= 0 && $0 <= maximumLength }) ?? true else {
                return false
            }
            field = AuriUIFormField(
                id: fieldID,
                kind: kind,
                label: label,
                placeholder: line.pair("placeholder"),
                initialValue: initialValue,
                isRequired: line.hasFlag("required"),
                minimumLength: minimumLength,
                maximumLength: maximumLength
            )

        case .select:
            let rawOptions = line.pairValues("opt")
            let options = rawOptions.compactMap(Self.formOption)
            guard options.count == rawOptions.count,
                  (2...8).contains(options.count),
                  Set(options.map(\.id)).count == options.count,
                  initialValue.isEmpty || options.contains(where: { $0.id == initialValue }) else {
                return false
            }
            field = AuriUIFormField(
                id: fieldID,
                kind: kind,
                label: label,
                initialValue: initialValue,
                isRequired: line.hasFlag("required"),
                options: options
            )

        case .date:
            guard !initialValue.isEmpty, AuriUIFormState.date(from: initialValue) != nil else {
                return false
            }
            field = AuriUIFormField(
                id: fieldID,
                kind: kind,
                label: label,
                initialValue: initialValue,
                isRequired: line.hasFlag("required")
            )

        case .slider:
            guard let minimum = line.pair("min").flatMap(Self.decimal),
                  let maximum = line.pair("max").flatMap(Self.decimal),
                  minimum < maximum else {
                return false
            }
            let step = line.pair("step").flatMap(Self.decimal) ?? 1
            let value = initialValue.isEmpty ? String(describing: minimum) : initialValue
            guard step > 0,
                  let decimalValue = Self.decimal(value),
                  decimalValue >= minimum,
                  decimalValue <= maximum else {
                return false
            }
            field = AuriUIFormField(
                id: fieldID,
                kind: kind,
                label: label,
                initialValue: value,
                isRequired: line.hasFlag("required"),
                minimum: minimum,
                maximum: maximum,
                step: step,
                unit: line.pair("unit")
            )
        }

        fields.append(field)
        open = .form(
            id: formID,
            title: title,
            capabilityID: capabilityID,
            confirmation: confirmation,
            fields: fields,
            submit: submit
        )
        return true
    }

    private mutating func appendFormSubmit(_ line: AuriUILexedLine) -> Bool {
        guard case .form(
            let formID,
            let title,
            let capabilityID,
            let confirmation,
            let fields,
            nil
        ) = open,
        !fields.isEmpty,
        let label = line.strings.first,
        !label.isEmpty,
        let action = line.action,
        action.capabilityID == capabilityID else {
            return false
        }

        open = .form(
            id: formID,
            title: title,
            capabilityID: capabilityID,
            confirmation: confirmation,
            fields: fields,
            submit: AuriUIFormSubmit(label: label, action: action)
        )
        return true
    }

    private static func formOption(_ raw: String) -> AuriUIFormOption? {
        guard let separator = raw.firstIndex(of: "=") else { return nil }
        let id = String(raw[..<separator]).trimmingCharacters(in: .whitespaces)
        let label = String(raw[raw.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        guard isIdentifier(id), !label.isEmpty else { return nil }
        return AuriUIFormOption(id: id, label: label)
    }

    private static func tile(from line: AuriUILexedLine) -> AuriUITile? {
        guard let title = line.strings.first, !title.isEmpty else { return nil }
        return AuriUITile(
            emoji: line.emoji,
            title: title,
            subtitle: line.strings.count > 1 ? line.strings[1] : nil,
            imageQuery: line.pair("img"),
            caption: line.pair("cap"),
            badge: line.pair("badge"),
            action: line.action
        )
    }

    // MARK: - Container / block lifecycle

    private mutating func openContainer(_ container: OpenContainer) {
        closeContainer()
        open = container
    }

    /// Materializes the open container into the active sink. Empty containers
    /// vanish silently — a title with no items renders nothing.
    private mutating func closeContainer() {
        guard let container = open else { return }
        open = nil
        guard let section = Self.materialize(container) else { return }
        appendClosedSection(section)
    }

    private static func materialize(
        _ container: OpenContainer,
        allowIncompleteChart: Bool = false
    ) -> AuriUISection? {
        switch container {
        case .row(let title, let items):
            return items.isEmpty ? nil : .row(title: title, items: items)
        case .posters(let title, let items):
            return items.isEmpty ? nil : .posters(title: title, items: items)
        case .menu(let title, let items):
            return items.isEmpty ? nil : .menu(title: title, items: items)
        case .grid(let title, let items):
            return items.isEmpty ? nil : .grid(title: title, items: items)
        case .cards(let cards):
            return cards.isEmpty ? nil : .cards(Array(cards.prefix(2)))
        case .steps(let title, let items):
            return items.isEmpty ? nil : .steps(title: title, items: items)
        case .facts(let title, let items):
            return items.isEmpty ? nil : .facts(title: title, items: items)
        case .bullets(let title, let checklist, let items):
            return items.isEmpty ? nil : .bullets(title: title, checklist: checklist, items: items)
        case .stats(let title, let items):
            return items.isEmpty ? nil : .stats(title: title, items: Array(items.prefix(4)))
        case .expand(let title, let items):
            return items.isEmpty ? nil : .expand(title: title, items: items)
        case .chips(let chips):
            return chips.isEmpty ? nil : .chips(chips)
        case .sources(let sources):
            return sources.isEmpty ? nil : .sources(sources)
        case .list(let title, let mode, let items):
            return items.isEmpty ? nil : .list(AuriUIOptionList(title: title, mode: mode, items: items))
        case .receipt(let title, let lines):
            return lines.isEmpty ? nil : .receipt(title: title, lines: lines)
        case .compare(let emoji, let columns, var groups, let groupTitle, let rows):
            if !rows.isEmpty {
                groups.append(AuriUIComparison.Group(title: groupTitle, rows: rows))
            }
            guard columns.count >= 2, !groups.isEmpty else { return nil }
            return .compare(AuriUIComparison(emoji: emoji, columns: columns, groups: groups))
        case .chart(let kind, let title, let unit, let points):
            guard !points.isEmpty else { return nil }
            let chart = AuriUIChart(kind: kind, title: title, unit: unit, points: points)
            guard allowIncompleteChart || chart.isComplete else { return nil }
            return .chart(chart)
        case .table(let title, let columns, let rows):
            guard (2...4).contains(columns.count), !rows.isEmpty else { return nil }
            return .table(AuriUITable(title: title, columns: columns, rows: rows))
        case .form(let id, let title, let capabilityID, let confirmation, let fields, let submit):
            guard (1...6).contains(fields.count), let submit else { return nil }
            return .form(AuriUIForm(
                id: id,
                title: title,
                capabilityID: capabilityID,
                confirmation: confirmation,
                fields: fields,
                submit: submit
            ))
        }
    }

    /// Routes a completed section to the page, tab, or document, in that
    /// order of specificity.
    private mutating func appendClosedSection(_ section: AuriUISection) {
        if currentPage != nil {
            currentPage?.sections.append(section)
        } else if inTabs {
            // Sections between `tabs` and the first `tab` have no home.
            if currentTab != nil {
                currentTab?.sections.append(section)
            } else {
                droppedLineCount += 1
            }
        } else {
            topSections.append(section)
        }
    }

    /// Leaf sections route through the same sink logic; returns false when
    /// the leaf lands between `tabs` and the first `tab`.
    private mutating func appendSection(_ section: AuriUISection) -> Bool {
        closeContainer()
        if currentPage == nil, inTabs, currentTab == nil { return false }
        appendClosedSection(section)
        return true
    }

    private mutating func flushCurrentTab() {
        if let tab = currentTab, !tab.sections.isEmpty {
            completedTabs.append(AuriUITab(title: tab.title, sections: tab.sections))
        }
        currentTab = nil
    }

    private mutating func closeTabs() {
        guard inTabs else { return }
        flushCurrentTab()
        inTabs = false
        let tabs = completedTabs
        completedTabs = []
        guard !tabs.isEmpty else { return }
        if currentPage != nil {
            currentPage?.sections.append(.tabs(tabs))
        } else {
            topSections.append(.tabs(tabs))
        }
    }

    private mutating func closePage() {
        if let page = currentPage, !page.sections.isEmpty {
            completedPages.append(AuriUIPage(forTitle: page.title, sections: page.sections, money: page.money))
        }
        currentPage = nil
    }

    // MARK: - Snapshot & reconciliation

    private mutating func rebuildDocument() {
        guard failure == nil else {
            document = AuriUIDocument()
            return
        }
        var sections = topSections
        if currentPage == nil, !inTabs, let open,
           let section = Self.materialize(open, allowIncompleteChart: true) {
            sections.append(section)
        }

        var pages = completedPages
        if var page = currentPage {
            if let open, let section = Self.materialize(open, allowIncompleteChart: true) {
                page.sections.append(section)
            }
            if !page.sections.isEmpty {
                pages.append(AuriUIPage(forTitle: page.title, sections: page.sections, money: page.money))
            }
        }

        document = AuriUIDocument(screen: screenHeader, summary: summary, money: money, sections: sections, pages: pages)
    }

    /// Joins pages to tiles exactly (case/punctuation-insensitive), rewriting
    /// `forTitle` to the tile's spelling. Orphan and duplicate pages drop.
    private mutating func reconcilePages() {
        guard !completedPages.isEmpty else { return }

        var keyToExact: [String: String] = [:]
        for title in Self.tileTitles(in: topSections) {
            let key = Self.titleKey(title)
            if keyToExact[key] == nil {
                keyToExact[key] = title
            }
        }
        guard !keyToExact.isEmpty else {
            completedPages = []
            return
        }

        var seen = Set<String>()
        completedPages = completedPages.compactMap { page in
            guard let exact = keyToExact[Self.titleKey(page.forTitle)], seen.insert(exact).inserted else {
                return nil
            }
            return AuriUIPage(forTitle: exact, sections: page.sections, money: page.money)
        }
    }

    private static func tileTitles(in sections: [AuriUISection]) -> [String] {
        var titles: [String] = []
        for section in sections {
            switch section {
            case .row(_, let items), .posters(_, let items), .grid(_, let items):
                titles.append(contentsOf: items.map(\.title))
            case .menu(_, let items):
                titles.append(contentsOf: items.map(\.title))
            case .cards(let cards):
                titles.append(contentsOf: cards.map(\.title))
            case .compare(let comparison):
                titles.append(contentsOf: comparison.columns.map(\.title))
            case .tabs(let tabs):
                for tab in tabs {
                    titles.append(contentsOf: tileTitles(in: tab.sections))
                }
            default:
                break
            }
        }
        return titles
    }

    private static func titleKey(_ title: String) -> String {
        String(String.UnicodeScalarView(
            title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        ))
    }

    // MARK: - Scalars

    static func decimal(_ raw: String) -> Decimal? {
        Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func slug(_ title: String) -> String {
        String(String.UnicodeScalarView(
            title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        ))
    }

    static func isIdentifier(_ value: String) -> Bool {
        guard let first = value.first, first.isLowercase, first.isASCII,
              value == value.lowercased() else { return false }
        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_")
        }
    }

    private static func stableID(_ value: String, ordinal: Int) -> String {
        let base = slug(value)
        return "\(base.isEmpty ? "row" : base)-\(ordinal)"
    }
}
