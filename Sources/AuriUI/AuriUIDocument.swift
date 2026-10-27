//
//  AuriUIDocument.swift
//  AuriUI
//
//  The parsed representation of an AuriUI v1 document. See GRAMMAR.md — that
//  file is normative; these types mirror it one construct per case.
//

import Foundation

/// A parsed AuriUI document: an inline chat answer (no `screen` header) or a
/// full-screen generated surface.
public struct AuriUIDocument: Equatable, Sendable {
    /// Present when the document is a screen; nil for inline answers.
    public var screen: AuriUIScreenHeader?
    /// From the `summary "…"` line on answer documents: 2–3 plain-text
    /// sentences that stand alone (spoken by TTS, stored as message text).
    /// Never rendered as a section.
    public var summary: String?
    /// Money context from the `state` line (base price and currency).
    public var money: AuriUIMoneyContext
    /// Visible sections, in document order.
    public var sections: [AuriUISection]
    /// Tap-to-open detail pages, reconciled to tile titles on `finish()`.
    public var pages: [AuriUIPage]

    /// A document with no surviving sections is unusable; callers fall back.
    public var isRenderable: Bool { !sections.isEmpty }

    public init(
        screen: AuriUIScreenHeader? = nil,
        summary: String? = nil,
        money: AuriUIMoneyContext = AuriUIMoneyContext(),
        sections: [AuriUISection] = [],
        pages: [AuriUIPage] = []
    ) {
        self.screen = screen
        self.summary = summary
        self.money = money
        self.sections = sections
        self.pages = pages
    }
}

/// `screen <snake_id> "Title" "Subtitle"? tint:<name>?`
public struct AuriUIScreenHeader: Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    /// Art direction: the flow's accent color name (renderer maps it to a
    /// platform color; unknown names fall back to the app accent).
    public var tint: String?

    public init(id: String, title: String, subtitle: String? = nil, tint: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
    }
}

/// `state base:12.50 cur:USD`
public struct AuriUIMoneyContext: Equatable, Sendable {
    public var base: Decimal
    public var currencyCode: String

    public init(base: Decimal = 0, currencyCode: String = "USD") {
        self.base = base
        self.currencyCode = currencyCode
    }
}

/// Where a `@url` action points. The model never mints URLs — it cites a
/// resource id from the screen's grounded DATA block, or defers to a
/// tap-time lookup. Literal URLs are tolerated for backward compatibility
/// but composers are instructed not to write them.
public enum AuriUIURLTarget: Equatable, Sendable {
    /// `@url(r3)` — a resource from the DATA block (guaranteed real).
    case resource(id: String)
    /// `@url(find:"dune part two official trailer")` — resolved by the
    /// backend at tap time.
    case lookup(query: String)
    /// `@url(https://…)` — a literal, e.g. copied from grounded data.
    case direct(URL)
}

/// A tap behavior. The first three cases come from the AuriUI wire format;
/// `hostCapability` exists only on trusted documents built in memory by the
/// containing app and has no lexer syntax.
public enum AuriUIAction: Equatable, Sendable {
    /// Send a message to the assistant (a chat turn).
    case send(prompt: String)
    /// Request the next generated screen; the brief doubles as the
    /// speculation prompt.
    case nav(brief: String)
    /// Open a link (see AuriUIURLTarget for reference semantics).
    case url(AuriUIURLTarget)
    /// Ask the containing app to run one registered, host-only capability.
    /// Model-authored AuriUI cannot construct this case.
    case hostCapability(id: String)

    /// The capability registry identifier required to execute this action.
    public var capabilityID: String {
        switch self {
        case .send:
            return "send"
        case .nav:
            return "nav"
        case .url:
            return "url"
        case .hostCapability(let id):
            return id
        }
    }
}

// MARK: - Sections

public enum AuriUISection: Equatable, Sendable {
    case intro(text: String)
    case header(emoji: String?, title: String, subtitle: String?)
    case hero(imageQuery: String?, caption: String?)
    case button(AuriUIButton)
    case row(title: String?, items: [AuriUITile])
    /// 2:3 cover-art carousel — films, shows, books, albums.
    case posters(title: String?, items: [AuriUITile])
    /// Rich commerce rows (dish/product: detail, price, trailing photo).
    case menu(title: String?, items: [AuriUIMenuItem])
    case grid(title: String?, items: [AuriUITile])
    case cards([AuriUICard])
    case steps(title: String?, items: [AuriUIStep])
    /// Icon-led feature rows (`facts`): the premium way to list qualities —
    /// emoji lead, bold title, one-line detail. Calmer than steps, richer
    /// than bullets.
    case facts(title: String?, items: [AuriUIStep])
    case bullets(title: String?, checklist: Bool, items: [String])
    case stats(title: String?, items: [AuriUIStat])
    case expand(title: String?, items: [AuriUIExpandable])
    case chips([AuriUIChip])
    case sources([AuriUISource])
    case list(AuriUIOptionList)
    case receipt(title: String?, lines: [AuriUIReceiptLine])
    case compare(AuriUIComparison)
    /// A bounded, grounded line or grouped-bar chart. The client owns the
    /// numeric scale, interaction, and accessible data-table fallback.
    case chart(AuriUIChart)
    /// A neutral 2–4 column matrix for standings, schedules, and compact facts.
    case table(AuriUITable)
    /// Typed, locally validated input that can submit only to a registered
    /// capability. Secure and transactional inputs are not part of v1.
    case form(AuriUIForm)
    case tabs([AuriUITab])
}

/// A tile in a `row`, `posters`, or `grid` container.
public struct AuriUITile: Equatable, Sendable {
    public var emoji: String?
    public var title: String
    public var subtitle: String?
    public var imageQuery: String?
    public var caption: String?
    /// Corner badge (`badge:"New"`) — genuine signals only.
    public var badge: String?
    public var action: AuriUIAction?

    public init(
        emoji: String? = nil,
        title: String,
        subtitle: String? = nil,
        imageQuery: String? = nil,
        caption: String? = nil,
        badge: String? = nil,
        action: AuriUIAction? = nil
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.imageQuery = imageQuery
        self.caption = caption
        self.badge = badge
        self.action = action
    }
}

/// One row in a `menu` container: title, one-line detail, unit price, and a
/// trailing photo — the commerce pattern (dishes, products).
public struct AuriUIMenuItem: Equatable, Sendable {
    public var emoji: String?
    public var title: String
    public var detail: String?
    public var price: Decimal?
    public var imageQuery: String?
    public var badge: String?
    public var action: AuriUIAction?

    public init(
        emoji: String? = nil,
        title: String,
        detail: String? = nil,
        price: Decimal? = nil,
        imageQuery: String? = nil,
        badge: String? = nil,
        action: AuriUIAction? = nil
    ) {
        self.emoji = emoji
        self.title = title
        self.detail = detail
        self.price = price
        self.imageQuery = imageQuery
        self.badge = badge
        self.action = action
    }
}

/// An entity card in a `cards` container.
public struct AuriUICard: Equatable, Sendable {
    public var emoji: String?
    public var title: String
    public var subtitle: String?
    public var imageQuery: String?
    public var stats: [AuriUIStatPair]
    public var action: AuriUIAction?

    public init(
        emoji: String? = nil,
        title: String,
        subtitle: String? = nil,
        imageQuery: String? = nil,
        stats: [AuriUIStatPair] = [],
        action: AuriUIAction? = nil
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.imageQuery = imageQuery
        self.stats = stats
        self.action = action
    }
}

/// One `s:"Label=Value"` pair on a card.
public struct AuriUIStatPair: Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct AuriUIStep: Equatable, Sendable {
    public var emoji: String?
    public var title: String
    public var detail: String?

    public init(emoji: String? = nil, title: String, detail: String? = nil) {
        self.emoji = emoji
        self.title = title
        self.detail = detail
    }
}

public struct AuriUIStat: Equatable, Sendable {
    public enum Trend: String, Equatable, Sendable {
        case up, down, flat
    }

    public var value: String
    public var label: String?
    public var trend: Trend?

    public init(value: String, label: String? = nil, trend: Trend? = nil) {
        self.value = value
        self.label = label
        self.trend = trend
    }
}

public struct AuriUIExpandable: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct AuriUIChip: Equatable, Sendable {
    public var label: String
    public var prompt: String

    public init(label: String, prompt: String) {
        self.label = label
        self.prompt = prompt
    }
}

public struct AuriUISource: Equatable, Sendable {
    public var title: String?
    public var urlString: String

    public init(title: String? = nil, urlString: String) {
        self.title = title
        self.urlString = urlString
    }
}

public enum AuriUIButtonState: Equatable, Sendable {
    case enabled
    case disabled
    case loading
}

public struct AuriUIButton: Equatable, Sendable {
    public var label: String
    public var isPrimary: Bool
    public var action: AuriUIAction?
    /// Host-authored documents can reflect app work without replacing the
    /// button with a second component. Wire-authored buttons stay enabled.
    public var state: AuriUIButtonState

    public init(
        label: String,
        isPrimary: Bool = false,
        action: AuriUIAction? = nil,
        state: AuriUIButtonState = .enabled
    ) {
        self.label = label
        self.isPrimary = isPrimary
        self.action = action
        self.state = state
    }
}

/// A selectable options list (`list … pick:<group>` or `list … multi`).
public struct AuriUIOptionList: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Single-select within a named group.
        case pick(group: String)
        /// Independently toggleable items.
        case multi
    }

    public var title: String?
    public var mode: Mode
    public var items: [AuriUIOption]

    public init(title: String? = nil, mode: Mode, items: [AuriUIOption]) {
        self.title = title
        self.mode = mode
        self.items = items
    }
}

public struct AuriUIOption: Equatable, Sendable {
    public var emoji: String?
    public var title: String
    public var subtitle: String?
    /// Stable identity within the list (`val:`); slugged from the title when
    /// the composer omits it.
    public var selectionValue: String
    public var price: Decimal
    public var selectedByDefault: Bool

    public init(
        emoji: String? = nil,
        title: String,
        subtitle: String? = nil,
        selectionValue: String,
        price: Decimal = 0,
        selectedByDefault: Bool = false
    ) {
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.selectionValue = selectionValue
        self.price = price
        self.selectedByDefault = selectedByDefault
    }
}

public struct AuriUIReceiptLine: Equatable, Sendable {
    public var label: String
    public var price: Decimal

    public init(label: String, price: Decimal) {
        self.label = label
        self.price = price
    }
}

public struct AuriUIComparison: Equatable, Sendable {
    /// One contender: `col "Tesla Model 3" img:"tesla model 3 press photo"`.
    /// Bare titles on the `compare` line become image-less columns.
    public struct Column: Equatable, Sendable {
        public var title: String
        public var imageQuery: String?

        public init(title: String, imageQuery: String? = nil) {
            self.title = title
            self.imageQuery = imageQuery
        }
    }

    public struct Row: Equatable, Sendable {
        public var label: String
        public var values: [String]
        /// 1-based winning column from `win:`.
        public var winner: Int?
        /// Optional short contextual badges aligned to `values` (`n1:`…`n3:`).
        public var notes: [String?]

        public init(
            label: String,
            values: [String],
            winner: Int? = nil,
            notes: [String?] = []
        ) {
            self.label = label
            self.values = values
            self.winner = winner
            self.notes = notes
        }
    }

    public struct Group: Equatable, Sendable {
        public var title: String?
        public var rows: [Row]

        public init(title: String? = nil, rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    public var emoji: String?
    public var columns: [Column]
    public var groups: [Group]

    public init(emoji: String? = nil, columns: [Column], groups: [Group]) {
        self.emoji = emoji
        self.columns = columns
        self.groups = groups
    }
}

/// `chart line|bar "Title" unit:"…"` followed by a complete rectangular set
/// of `point "X label" "Series" v:<number>` lines.
public struct AuriUIChart: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case line
        case bar
    }

    public struct Point: Identifiable, Equatable, Sendable {
        public var id: String
        public var xLabel: String
        public var series: String
        public var value: Decimal

        public init(id: String, xLabel: String, series: String, value: Decimal) {
            self.id = id
            self.xLabel = xLabel
            self.series = series
            self.value = value
        }
    }

    public static let maximumXValueCount = 12
    public static let maximumSeriesCount = 3
    public static let maximumPointCount = maximumXValueCount * maximumSeriesCount
    // Decimal integer literals use Int, which is 32-bit on watchOS arm64_32.
    public static let maximumMagnitude = Decimal(Int64(1_000_000_000_000_000))

    public var kind: Kind
    public var title: String
    public var unit: String
    public var points: [Point]

    public init(kind: Kind, title: String, unit: String, points: [Point]) {
        self.kind = kind
        self.title = title
        self.unit = unit
        self.points = points
    }

    /// X labels in their first-seen order. The order is semantic for line
    /// charts and drives the table rows for both chart kinds.
    public var xLabels: [String] {
        Self.unique(points.map(\.xLabel))
    }

    /// Series in their first-seen order, used for stable legends and colors.
    public var seriesNames: [String] {
        Self.unique(points.map(\.series))
    }

    /// Complete charts are rectangular: every series has exactly one value
    /// for every X label. This prevents a generated chart from implying a
    /// comparison where data is missing.
    public var isComplete: Bool {
        let xLabels = xLabels
        let seriesNames = seriesNames
        guard !title.isEmpty,
              title.count <= 80,
              !unit.isEmpty,
              unit.count <= 24,
              (2...Self.maximumXValueCount).contains(xLabels.count),
              (1...Self.maximumSeriesCount).contains(seriesNames.count),
              points.count == xLabels.count * seriesNames.count,
              points.count <= Self.maximumPointCount,
              xLabels.allSatisfy({ !$0.isEmpty && $0.count <= 32 }),
              seriesNames.allSatisfy({ !$0.isEmpty && $0.count <= 32 }),
              points.allSatisfy({
                  $0.value >= -Self.maximumMagnitude && $0.value <= Self.maximumMagnitude
              }) else {
            return false
        }

        let coordinates = Set(points.map { Coordinate(xLabel: $0.xLabel, series: $0.series) })
        guard coordinates.count == points.count else { return false }

        return seriesNames.allSatisfy { series in
            Set(points.lazy.filter { $0.series == series }.map(\.xLabel)) == Set(xLabels)
        }
    }

    public func point(xLabel: String, series: String) -> Point? {
        points.first { $0.xLabel == xLabel && $0.series == series }
    }

    private struct Coordinate: Hashable {
        let xLabel: String
        let series: String
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// `table "Standings"` followed by `tcol` headers and `trow` values.
public struct AuriUITable: Equatable, Sendable {
    public struct Column: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct Cell: Identifiable, Equatable, Sendable {
        public var id: String
        public var text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public var id: String
        public var cells: [Cell]
        public var isHighlighted: Bool

        public var values: [String] { cells.map(\.text) }

        public init(id: String, cells: [Cell], isHighlighted: Bool = false) {
            self.id = id
            self.cells = cells
            self.isHighlighted = isHighlighted
        }
    }

    public var title: String?
    public var columns: [Column]
    public var rows: [Row]

    public init(title: String? = nil, columns: [Column], rows: [Row]) {
        self.title = title
        self.columns = columns
        self.rows = rows
    }
}

/// A capability-gated form. The model declares fields and a submit template;
/// the client owns values, validation, confirmation, and action execution.
public struct AuriUIForm: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var capabilityID: String
    public var confirmation: String?
    /// Field IDs are unique within a form. If an ID repeats, the first field
    /// wins, matching the streaming parser's handling of duplicate fields.
    public var fields: [AuriUIFormField] {
        didSet { fields = Self.uniqueFields(fields) }
    }
    public var submit: AuriUIFormSubmit

    public init(
        id: String,
        title: String,
        capabilityID: String,
        confirmation: String? = nil,
        fields: [AuriUIFormField],
        submit: AuriUIFormSubmit
    ) {
        self.id = id
        self.title = title
        self.capabilityID = capabilityID
        self.confirmation = confirmation
        self.fields = Self.uniqueFields(fields)
        self.submit = submit
    }

    private static func uniqueFields(_ fields: [AuriUIFormField]) -> [AuriUIFormField] {
        var seen = Set<String>()
        return fields.filter { seen.insert($0.id).inserted }
    }
}

public struct AuriUIFormSubmit: Equatable, Sendable {
    public var label: String
    public var action: AuriUIAction

    public init(label: String, action: AuriUIAction) {
        self.label = label
        self.action = action
    }
}

public struct AuriUIFormOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct AuriUIFormField: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case text
        case textArea = "textarea"
        case select
        case date
        case slider
    }

    public var id: String
    public var kind: Kind
    public var label: String
    public var placeholder: String?
    public var initialValue: String
    public var isRequired: Bool
    public var minimumLength: Int?
    public var maximumLength: Int?
    public var minimum: Decimal?
    public var maximum: Decimal?
    public var step: Decimal?
    public var unit: String?
    public var options: [AuriUIFormOption]

    public init(
        id: String,
        kind: Kind,
        label: String,
        placeholder: String? = nil,
        initialValue: String = "",
        isRequired: Bool = false,
        minimumLength: Int? = nil,
        maximumLength: Int? = nil,
        minimum: Decimal? = nil,
        maximum: Decimal? = nil,
        step: Decimal? = nil,
        unit: String? = nil,
        options: [AuriUIFormOption] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.isRequired = isRequired
        self.minimumLength = minimumLength
        self.maximumLength = maximumLength
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.unit = unit
        self.options = options
    }
}

public struct AuriUITab: Equatable, Sendable {
    public var title: String
    public var sections: [AuriUISection]

    public init(title: String, sections: [AuriUISection]) {
        self.title = title
        self.sections = sections
    }
}

/// A tap-to-open detail page (`page "<tile title>"`).
public struct AuriUIPage: Equatable, Sendable {
    public var forTitle: String
    public var sections: [AuriUISection]
    /// A page's explicit `state` overrides the containing screen's money
    /// context. Pages without a state line inherit that context.
    public var money: AuriUIMoneyContext?

    public init(forTitle: String, sections: [AuriUISection], money: AuriUIMoneyContext? = nil) {
        self.forTitle = forTitle
        self.sections = sections
        self.money = money
    }
}

// MARK: - Navigation briefs

extension AuriUIDocument {
    /// Every `@nav` brief reachable from this document's visible sections
    /// (tiles, cards, buttons — tabs included), deduplicated in document
    /// order. Feed to a speculation engine to pre-compose likely next
    /// screens. Briefs containing interpolation placeholders depend on live
    /// selection state; callers decide whether to expand or skip them.
    public var navBriefs: [String] {
        var seen = Set<String>()
        var briefs: [String] = []

        func collect(_ action: AuriUIAction?) {
            if case .nav(let brief) = action, seen.insert(brief).inserted {
                briefs.append(brief)
            }
        }

        func walk(_ sections: [AuriUISection]) {
            for section in sections {
                switch section {
                case .button(let button):
                    collect(button.action)
                case .row(_, let items), .posters(_, let items), .grid(_, let items):
                    items.forEach { collect($0.action) }
                case .menu(_, let items):
                    items.forEach { collect($0.action) }
                case .cards(let cards):
                    cards.forEach { collect($0.action) }
                case .form(let form):
                    collect(form.submit.action)
                case .tabs(let tabs):
                    tabs.forEach { walk($0.sections) }
                default:
                    break
                }
            }
        }

        walk(sections)
        return briefs
    }
}
