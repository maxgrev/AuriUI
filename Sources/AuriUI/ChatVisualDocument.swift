//
//  ChatVisualDocument.swift
//  Auri
//
//  Swift mirror of the Auri Visual Document v1 contract produced by the
//  auri-visual-orchestrator worker (CloudflareWorkers/auri-visual-orchestrator).
//  Decoding is deliberately lossy: unknown section types and malformed
//  sections are skipped so the document survives protocol drift in either
//  direction.
//

import Foundation

public struct ChatVisualDocument: Decodable, Hashable, Sendable {
    public let summary: String
    public let sections: [ChatVisualSection]
    /// Tap-to-open detail pages from the trailing `detail_pages` section,
    /// keyed by normalized tile title. Emitted last by the orchestrator so
    /// tiles stream in early; joined back to tiles at render time.
    public let detailPages: [String: [ChatVisualSection]]

    private enum CodingKeys: String, CodingKey {
        case summary, sections
    }

    public init(summary: String, sections: [ChatVisualSection], detailPages: [String: [ChatVisualSection]] = [:]) {
        self.summary = summary
        self.sections = sections
        self.detailPages = detailPages
    }

    /// Lookup key for joining a tile to its detail page.
    public static func detailKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = try container.decode(String.self, forKey: .summary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .summary, in: container, debugDescription: "Empty summary")
        }

        var sectionsContainer = try container.nestedUnkeyedContainer(forKey: .sections)
        var sections: [ChatVisualSection] = []
        var detailPages: [String: [ChatVisualSection]] = [:]
        var rawIndex = 0
        while !sectionsContainer.isAtEnd {
            // Always consume the element; a malformed section must not stall the loop.
            guard let raw = try? sectionsContainer.decode(RawVisualSection.self) else {
                _ = try? sectionsContainer.decode(AnyDecodableValue.self)
                rawIndex += 1
                continue
            }

            // detail_pages is metadata, not a rendered section: fold it into
            // the title-keyed lookup instead of the section list. First page
            // wins on duplicate titles — a duplicated for_title must never
            // reassign an earlier tile's content.
            if raw.type == "detail_pages" {
                for (pageIndex, page) in (raw.pages ?? []).enumerated() {
                    guard let title = page.forTitle.nonEmpty else { continue }
                    let key = Self.detailKey(title)
                    guard detailPages[key] == nil else { continue }
                    let pageSections = page.sections.enumerated().compactMap { sectionIndex, rawSection in
                        ChatVisualSection(raw: rawSection, allowsTabs: false, id: "p\(pageIndex)-\(sectionIndex)")
                    }
                    if !pageSections.isEmpty {
                        detailPages[key] = pageSections
                    }
                }
                rawIndex += 1
                continue
            }

            // Deterministic, position-based ids: identical across incremental
            // partial parses and the final document, so SwiftUI keeps section
            // identity while streaming instead of replaying every entrance.
            if let section = ChatVisualSection(raw: raw, allowsTabs: true, id: "s\(rawIndex)") {
                sections.append(section)
            }
            rawIndex += 1
        }

        guard !sections.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .sections, in: container, debugDescription: "No decodable sections")
        }

        self.summary = summary
        // Join detail pages into their tiles AT DECODE TIME, so a tile's
        // detailSections is plain value data. When the merged document
        // replaces the provisional one, the tile values actually change and
        // SwiftUI re-renders them through ordinary diffing — no sideband
        // (environment) propagation for correctness to depend on.
        self.sections = Self.injectingDetailPages(sections, pages: detailPages)
        self.detailPages = detailPages
    }

    private static func injectingDetailPages(
        _ sections: [ChatVisualSection],
        pages: [String: [ChatVisualSection]]
    ) -> [ChatVisualSection] {
        guard !pages.isEmpty else {
            return sections
        }

        func joinedItems(_ items: [VisualItem]) -> [VisualItem] {
            items.map { item in
                guard item.detailSections == nil, let title = item.title,
                      let pageSections = pages[detailKey(title)] else {
                    return item
                }
                var item = item
                item.detailSections = pageSections
                return item
            }
        }

        return sections.map { section in
            switch section.kind {
            case .entityCards(let cards):
                let joinedCards = cards.map { card -> VisualCard in
                    guard card.detailSections == nil, let title = card.title,
                          let pageSections = pages[detailKey(title)] else {
                        return card
                    }
                    var card = card
                    card.detailSections = pageSections
                    return card
                }
                return ChatVisualSection(id: section.id, kind: .entityCards(cards: joinedCards))
            case .mediaRow(let items):
                return ChatVisualSection(id: section.id, kind: .mediaRow(items: joinedItems(items)))
            case .grid(let title, let items):
                return ChatVisualSection(id: section.id, kind: .grid(title: title, items: joinedItems(items)))
            default:
                return section
            }
        }
    }
}

public struct ChatVisualSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: Kind

    public enum Kind: Hashable, Sendable {
        case intro(text: String)
        case header(emoji: String?, title: String, subtitle: String?)
        case entityCards(cards: [VisualCard])
        case mediaRow(items: [VisualItem])
        case comparison(columns: [VisualColumn], groups: [VisualComparisonGroup])
        case grid(title: String?, items: [VisualItem])
        case steps(title: String?, items: [VisualItem])
        case bullets(title: String?, isChecklist: Bool, items: [VisualItem])
        case stats(items: [VisualItem])
        case tabs(tabs: [VisualTab])
        case expandables(items: [VisualItem])
        case chips(items: [VisualItem])
        case buttons(items: [VisualItem])
        case sources(items: [VisualItem])
    }

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    // Maps a raw wire section to a typed kind, enforcing the same per-type
    // minimum content rules as the worker's validator. Returns nil (skip)
    // when the section can't render meaningfully. `id` must be deterministic
    // for stable SwiftUI identity across streaming re-parses.
    init?(raw: RawVisualSection, allowsTabs: Bool, id: String) {
        switch raw.type {
        case "intro":
            guard let text = raw.text.nonEmpty else { return nil }
            self.init(id: id, kind: .intro(text: text))
        case "header":
            guard let title = raw.title.nonEmpty else { return nil }
            self.init(id: id, kind: .header(emoji: raw.emoji.nonEmpty, title: title, subtitle: raw.subtitle.nonEmpty))
        case "entity_cards":
            let cards = (raw.cards ?? []).filter { $0.title.nonEmpty != nil }
            guard !cards.isEmpty else { return nil }
            self.init(id: id, kind: .entityCards(cards: cards))
        case "media_row":
            let items = (raw.items ?? []).filter { $0.title.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .mediaRow(items: items))
        case "comparison":
            let columns = (raw.columns ?? []).filter { $0.title.nonEmpty != nil }
            let groups = (raw.groups ?? []).filter { !$0.rows.isEmpty }
            guard columns.count >= 2, !groups.isEmpty else { return nil }
            self.init(id: id, kind: .comparison(columns: columns, groups: groups))
        case "grid":
            let items = (raw.items ?? []).filter { $0.title.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .grid(title: raw.title.nonEmpty, items: items))
        case "steps":
            let items = (raw.items ?? []).filter { $0.title.nonEmpty != nil || $0.detail.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .steps(title: raw.title.nonEmpty, items: items))
        case "bullets":
            let items = (raw.items ?? []).filter { $0.text.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .bullets(title: raw.title.nonEmpty, isChecklist: raw.style == "check", items: items))
        case "stats":
            let items = (raw.items ?? []).filter { $0.value.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .stats(items: items))
        case "tabs":
            guard allowsTabs else { return nil }
            let tabs = (raw.tabs ?? []).enumerated().compactMap { tabIndex, rawTab -> VisualTab? in
                guard let title = rawTab.title.nonEmpty else { return nil }
                // Tabs never nest inside tabs.
                let sections = rawTab.sections.enumerated().compactMap { sectionIndex, rawSection in
                    ChatVisualSection(raw: rawSection, allowsTabs: false, id: "\(id)-t\(tabIndex)-\(sectionIndex)")
                }
                guard !sections.isEmpty else { return nil }
                return VisualTab(title: title, sections: sections)
            }
            guard !tabs.isEmpty else { return nil }
            self.init(id: id, kind: .tabs(tabs: tabs))
        case "expandables":
            let items = (raw.items ?? []).filter { $0.title.nonEmpty != nil && $0.body.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .expandables(items: items))
        case "chips":
            let items = (raw.items ?? []).filter { $0.label.nonEmpty != nil && $0.prompt.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .chips(items: items))
        case "buttons":
            let items = (raw.items ?? []).filter { $0.label.nonEmpty != nil && $0.action != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .buttons(items: items))
        case "sources":
            let items = (raw.items ?? []).filter { $0.url.nonEmpty != nil }
            guard !items.isEmpty else { return nil }
            self.init(id: id, kind: .sources(items: items))
        default:
            return nil
        }
    }
}

// MARK: - Payload types

public struct VisualItem: Decodable, Hashable, Sendable {
    public let emoji: String?
    public let imageURL: URL?
    /// Original-resolution image for the tap-to-open detail header; the tile
    /// itself uses the fast thumbnail in `imageURL`.
    public let fullImageURL: URL?
    public let title: String?
    public let subtitle: String?
    public let text: String?
    public let detail: String?
    public let caption: String?
    public let value: String?
    public let label: String?
    public let trend: VisualTrend?
    public let body: String?
    public let prompt: String?
    public let url: String?
    public let domain: String?
    public let action: VisualAction?
    /// Embedded tap-to-open detail page (media/entity/grid tiles).
    public internal(set) var detailSections: [ChatVisualSection]?

    private enum CodingKeys: String, CodingKey {
        case emoji, title, subtitle, text, detail, caption, value, label, body, prompt, url, domain, action, trend
        case imageURL = "image_url"
        case fullImageURL = "full_image_url"
        case detailSections = "detail_sections"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji).nonEmpty
        imageURL = Self.httpsURL(try container.decodeIfPresent(String.self, forKey: .imageURL))
        fullImageURL = Self.httpsURL(try container.decodeIfPresent(String.self, forKey: .fullImageURL))
        title = try container.decodeIfPresent(String.self, forKey: .title).nonEmpty
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle).nonEmpty
        text = try container.decodeIfPresent(String.self, forKey: .text).nonEmpty
        detail = try container.decodeIfPresent(String.self, forKey: .detail).nonEmpty
        caption = try container.decodeIfPresent(String.self, forKey: .caption).nonEmpty
        value = try container.decodeIfPresent(String.self, forKey: .value).nonEmpty
        label = try container.decodeIfPresent(String.self, forKey: .label).nonEmpty
        trend = VisualTrend(lenient: (try? container.decodeIfPresent(String.self, forKey: .trend)) ?? nil)
        body = try container.decodeIfPresent(String.self, forKey: .body).nonEmpty
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt).nonEmpty
        url = try container.decodeIfPresent(String.self, forKey: .url).nonEmpty
        domain = try container.decodeIfPresent(String.self, forKey: .domain).nonEmpty
        action = try? container.decodeIfPresent(VisualAction.self, forKey: .action)
        detailSections = decodeLossyDetailSections(container, forKey: .detailSections)
    }

    static func httpsURL(_ string: String?) -> URL? {
        guard let value = string.nonEmpty,
              let url = URL(string: value),
              url.scheme == "https" else {
            return nil
        }
        return url
    }

    /// Direct construction for AuriUI adapters (generated surfaces reuse the
    /// v1 section views). Not part of the wire format.
    public init(
        emoji: String? = nil,
        imageURL: URL? = nil,
        fullImageURL: URL? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        text: String? = nil,
        detail: String? = nil,
        caption: String? = nil,
        value: String? = nil,
        label: String? = nil,
        trend: VisualTrend? = nil,
        body: String? = nil,
        prompt: String? = nil,
        url: String? = nil,
        domain: String? = nil,
        action: VisualAction? = nil
    ) {
        self.emoji = emoji
        self.imageURL = imageURL
        self.fullImageURL = fullImageURL
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.detail = detail
        self.caption = caption
        self.value = value
        self.label = label
        self.trend = trend
        self.body = body
        self.prompt = prompt
        self.url = url
        self.domain = domain
        self.action = action
        self.detailSections = nil
    }
}

public struct VisualCard: Decodable, Hashable, Sendable {
    public let emoji: String?
    public let imageURL: URL?
    /// Original-resolution image for the tap-to-open detail header.
    public let fullImageURL: URL?
    public let title: String?
    public let subtitle: String?
    public let stats: [VisualStat]?
    public let action: VisualAction?
    /// Embedded tap-to-open detail page.
    public internal(set) var detailSections: [ChatVisualSection]?

    private enum CodingKeys: String, CodingKey {
        case emoji, title, subtitle, stats, action
        case imageURL = "image_url"
        case fullImageURL = "full_image_url"
        case detailSections = "detail_sections"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji).nonEmpty
        imageURL = VisualItem.httpsURL(try container.decodeIfPresent(String.self, forKey: .imageURL))
        fullImageURL = VisualItem.httpsURL(try container.decodeIfPresent(String.self, forKey: .fullImageURL))
        title = try container.decodeIfPresent(String.self, forKey: .title).nonEmpty
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle).nonEmpty
        stats = try? container.decodeIfPresent([VisualStat].self, forKey: .stats)
        action = try? container.decodeIfPresent(VisualAction.self, forKey: .action)
        detailSections = decodeLossyDetailSections(container, forKey: .detailSections)
    }

    /// Direct construction for AuriUI adapters. Not part of the wire format.
    public init(
        emoji: String? = nil,
        imageURL: URL? = nil,
        fullImageURL: URL? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        stats: [VisualStat]? = nil,
        action: VisualAction? = nil
    ) {
        self.emoji = emoji
        self.imageURL = imageURL
        self.fullImageURL = fullImageURL
        self.title = title
        self.subtitle = subtitle
        self.stats = stats
        self.action = action
        self.detailSections = nil
    }
}

// Decodes an embedded detail page lossily: malformed sections are skipped,
// tabs are not allowed inside details, and ids are deterministic within the
// detail's own ForEach scope.
private func decodeLossyDetailSections<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) -> [ChatVisualSection]? {
    guard var nested = try? container.nestedUnkeyedContainer(forKey: key) else {
        return nil
    }
    var sections: [ChatVisualSection] = []
    var rawIndex = 0
    while !nested.isAtEnd {
        guard let raw = try? nested.decode(RawVisualSection.self) else {
            _ = try? nested.decode(AnyDecodableValue.self)
            rawIndex += 1
            continue
        }
        if let section = ChatVisualSection(raw: raw, allowsTabs: false, id: "d\(rawIndex)") {
            sections.append(section)
        }
        rawIndex += 1
    }
    return sections.isEmpty ? nil : sections
}

public struct VisualStat: Decodable, Hashable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct VisualColumn: Decodable, Hashable, Sendable {
    public let emoji: String?
    public let imageURL: URL?
    public let title: String?

    private enum CodingKeys: String, CodingKey {
        case emoji, title
        case imageURL = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji).nonEmpty
        imageURL = VisualItem.httpsURL(try container.decodeIfPresent(String.self, forKey: .imageURL))
        title = try container.decodeIfPresent(String.self, forKey: .title).nonEmpty
    }

    /// Direct construction for AuriUI adapters. Not part of the wire format.
    public init(emoji: String? = nil, imageURL: URL? = nil, title: String? = nil) {
        self.emoji = emoji
        self.imageURL = imageURL
        self.title = title
    }
}

public struct VisualComparisonGroup: Decodable, Hashable, Sendable {
    public let emoji: String?
    public let title: String?
    public let rows: [VisualComparisonRow]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji).nonEmpty
        title = try container.decodeIfPresent(String.self, forKey: .title).nonEmpty
        rows = (try? container.decodeIfPresent([VisualComparisonRow].self, forKey: .rows)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case emoji, title, rows
    }

    /// Direct construction for AuriUI adapters. Not part of the wire format.
    public init(emoji: String? = nil, title: String? = nil, rows: [VisualComparisonRow]) {
        self.emoji = emoji
        self.title = title
        self.rows = rows
    }
}

public struct VisualComparisonRow: Decodable, Hashable, Sendable {
    public let label: String
    public let values: [VisualComparisonValue]

    public init(label: String, values: [VisualComparisonValue]) {
        self.label = label
        self.values = values
    }
}

public struct VisualComparisonValue: Decodable, Hashable, Sendable {
    public let text: String
    public let verdict: VisualVerdict
    public let note: String?

    private enum CodingKeys: String, CodingKey {
        case text, verdict, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        verdict = VisualVerdict(lenient: (try? container.decodeIfPresent(String.self, forKey: .verdict)) ?? nil)
        note = try container.decodeIfPresent(String.self, forKey: .note).nonEmpty
    }

    /// Direct construction for AuriUI adapters. Not part of the wire format.
    public init(text: String, verdict: VisualVerdict = .neutral, note: String? = nil) {
        self.text = text
        self.verdict = verdict
        self.note = note
    }
}

public struct VisualTab: Hashable, Sendable {
    public let title: String
    public let sections: [ChatVisualSection]

    public init(title: String, sections: [ChatVisualSection]) {
        self.title = title
        self.sections = sections
    }
}

public enum VisualVerdict: String, Sendable {
    case good, bad, neutral

    // Unknown verdicts render as neutral rather than failing the row.
    init(lenient rawValue: String?) {
        switch rawValue ?? "" {
        case "good": self = .good
        case "bad": self = .bad
        default: self = .neutral
        }
    }
}

public enum VisualTrend: String, Sendable {
    case up, down, flat

    init?(lenient rawValue: String?) {
        switch rawValue ?? "" {
        case "up": self = .up
        case "down": self = .down
        case "flat": self = .flat
        default: return nil
        }
    }
}

public enum VisualAction: Hashable, Sendable {
    case sendPrompt(String)
    case openURL(URL)
    /// UI-only, never decoded from the wire: card/media taps map their
    /// `sendPrompt` to this so the composer is prefilled (visible, editable)
    /// instead of silently firing a message. Chips and buttons still send.
    case composePrompt(String)
    /// UI-only, never decoded from the wire: an AuriUI `@nav` brief pushed
    /// through the reused v1 section views on generated surfaces. Chat
    /// answers ignore it.
    case navigate(String)
    /// UI-only, never decoded from the wire: opens an AuriUI detail page by
    /// its tile title on generated surfaces. Chat answers ignore it.
    case openPage(String)
}

extension VisualAction: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, prompt, url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "send_prompt":
            guard let prompt = try container.decodeIfPresent(String.self, forKey: .prompt).nonEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .prompt, in: container, debugDescription: "Missing prompt")
            }
            self = .sendPrompt(prompt)
        case "open_url":
            guard let urlString = try container.decodeIfPresent(String.self, forKey: .url).nonEmpty,
                  let url = URL(string: urlString),
                  url.scheme == "https" || url.scheme == "http" else {
                throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Missing or non-web URL")
            }
            self = .openURL(url)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown action kind")
        }
    }
}

// MARK: - Wire-format helpers

// The raw, fully-optional wire shape of one section. Kept internal; the app
// consumes the typed `ChatVisualSection.Kind` instead.
struct RawVisualSection: Decodable {
    let type: String
    let text: String?
    let emoji: String?
    let title: String?
    let subtitle: String?
    let style: String?
    let cards: [VisualCard]?
    let columns: [VisualColumn]?
    let groups: [VisualComparisonGroup]?
    let items: [VisualItem]?
    let tabs: [RawVisualTab]?
    let pages: [RawVisualDetailPage]?
}

struct RawVisualDetailPage: Decodable {
    let forTitle: String?
    let sections: [RawVisualSection]

    private enum CodingKeys: String, CodingKey {
        case forTitle = "for_title"
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forTitle = try container.decodeIfPresent(String.self, forKey: .forTitle)
        var sectionsContainer = try container.nestedUnkeyedContainer(forKey: .sections)
        var decoded: [RawVisualSection] = []
        while !sectionsContainer.isAtEnd {
            guard let raw = try? sectionsContainer.decode(RawVisualSection.self) else {
                _ = try? sectionsContainer.decode(AnyDecodableValue.self)
                continue
            }
            decoded.append(raw)
        }
        sections = decoded
    }
}

struct RawVisualTab: Decodable {
    let title: String?
    let sections: [RawVisualSection]

    private enum CodingKeys: String, CodingKey {
        case title, sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        var sectionsContainer = try container.nestedUnkeyedContainer(forKey: .sections)
        var decoded: [RawVisualSection] = []
        while !sectionsContainer.isAtEnd {
            guard let raw = try? sectionsContainer.decode(RawVisualSection.self) else {
                _ = try? sectionsContainer.decode(AnyDecodableValue.self)
                continue
            }
            decoded.append(raw)
        }
        sections = decoded
    }
}

// Consumes and discards one arbitrary JSON value (used to skip malformed
// elements without stalling unkeyed containers).
struct AnyDecodableValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        if (try? container.decode(String.self)) != nil { return }
        if (try? container.decode([AnyDecodableValue].self)) != nil { return }
        if (try? container.decode([String: AnyDecodableValue].self)) != nil { return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
