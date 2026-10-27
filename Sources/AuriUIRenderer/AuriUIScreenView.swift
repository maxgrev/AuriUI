#if os(iOS) || os(macOS)
//
//  AuriUIScreenView.swift
//  Auri
//
//  Renders one generated surface: streams sections onto screen as the parser
//  yields them. Shared section shapes reuse the v1 Visual view library via
//  lightweight adapters; v2-only constructs (hero, lists, receipt, CTA) come
//  from AuriUISectionViews.
//

import AuriUI
import MarkdownUI
import SwiftUI

/// What a generated surface asks its host to do. Actions arrive already
/// interpolated ({total}/{selections} expanded).
@available(iOS 17.0, macOS 14.0, *)
public enum AuriUISurfaceAction: Equatable, Sendable {
    case navigate(brief: String, parentID: String)
    case sendToChat(prompt: String)
    case openURL(URL)
    case hostCapability(id: String)
}

@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIScreenView: View {
    let session: AuriUIScreenSession
    let canNavigateBack: Bool
    let onNavigateBack: () -> Void
    let onClose: () -> Void
    let onSurfaceAction: (AuriUISurfaceAction) -> Void
    private let accentColor: Color

    public init(
        session: AuriUIScreenSession,
        canNavigateBack: Bool = false,
        onNavigateBack: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        accentColor: Color = .accentColor,
        onSurfaceAction: @escaping (AuriUISurfaceAction) -> Void
    ) {
        self.session = session
        self.canNavigateBack = canNavigateBack
        self.onNavigateBack = onNavigateBack
        self.onClose = onClose
        self.accentColor = accentColor
        self.onSurfaceAction = onSurfaceAction
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        AuriUITintPalette.color(named: session.document.screen?.tint) ?? accentColor
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let subtitle = session.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                switch session.phase {
                case .composing where session.document.sections.isEmpty:
                    VisualSkeletonView()
                case .failed(let message) where session.document.sections.isEmpty:
                    failureView(message)
                default:
                    AuriUISectionsColumn(
                        sections: session.document.sections,
                        session: session,
                        onSurfaceAction: onSurfaceAction
                    )
                    .disabled(isIncomplete)

                    switch session.phase {
                    case .composing:
                        AuriUIComposingFooter()
                    case .failed(let message):
                        incompleteView(message)
                    case .ready:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: VisualLayout.columnMaxWidth)
            .frame(maxWidth: .infinity, alignment: VisualLayout.columnAlignment)
        }
        // Art direction: the flow's tint colors every accent and casts a
        // faint ambient wash from the top — each flow feels like its own app.
        .background(alignment: .top) {
            LinearGradient(colors: [accent.opacity(0.085), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
                .ignoresSafeArea(edges: .top)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: session.document.screen?.tint)
        }
        .environment(\.auriUIAccent, accent)
        .tint(accent)
        .sheet(
            item: Binding(
                get: { session.presentedPage },
                set: { session.presentedPage = $0 }
            ),
            onDismiss: session.dismissPresentedPage
        ) { presented in
            AuriUIPageSheet(page: presented.page, session: session) { action in
                // A page handing off (nav/chat/url) dismisses itself first.
                session.presentedPage = nil
                onSurfaceAction(action)
            }
            .environment(\.auriUIAccent, accent)
            .tint(accent)
        }
        #if os(macOS)
        .safeAreaInset(edge: .top, spacing: 0) {
            AuriUIMacDetailHeader(
                title: session.title ?? "",
                canNavigateBack: canNavigateBack,
                onNavigateBack: onNavigateBack,
                onClose: onClose
            )
        }
        #else
        .navigationTitle(session.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            session.start()
        }
        .onAppear {
            session.becameVisible()
        }
        .onDisappear {
            session.cancel()
            session.dismissPresentedPage()
        }
    }

    private var isIncomplete: Bool {
        // Streamed sections remain usable; failed partial output cannot act.
        if case .failed = session.phase {
            return true
        }
        return false
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                session.retry()
            } label: {
                Label(String(localized: "Try again"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("auriui.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func incompleteView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Label(
                String(localized: "This screen is incomplete."),
                systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                session.retry()
            } label: {
                Label(String(localized: "Try again"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("auriui.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
}

#if os(macOS)
/// Generated detail sheets need their chrome inside the presented surface:
/// a window toolbar item has no visible row in this embedded sheet context.
/// Equal-width leading and trailing control regions keep the title optically
/// centered without offsets, even when a Back button joins Close.
@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIMacDetailHeader: View {
    let title: String
    let canNavigateBack: Bool
    let onNavigateBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            controls

            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            controlsPlaceholder
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                closeButtonLabel
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(String(localized: "Close"))
            .accessibilityLabel(Text(String(localized: "Close")))

            if canNavigateBack {
                Button(action: onNavigateBack) {
                    backButtonLabel
                }
                .buttonStyle(.plain)
                .help(String(localized: "Back"))
                .accessibilityLabel(Text(String(localized: "Back")))
            }
        }
    }

    /// Mirrors the visible controls without duplicating interactive buttons,
    /// so the middle title receives exactly symmetric layout space.
    private var controlsPlaceholder: some View {
        HStack(spacing: 6) {
            closeButtonLabel
                .hidden()

            if canNavigateBack {
                backButtonLabel
                    .hidden()
            }
        }
        .accessibilityHidden(true)
    }

    private var backButtonLabel: some View {
        Image(systemName: "chevron.backward")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var closeButtonLabel: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.ultraThinMaterial, in: Circle())
    }
}
#endif

// MARK: - Sections column

@available(iOS 17.0, macOS 14.0, *)
public struct AuriUISectionsColumn: View {
    let sections: [AuriUISection]
    let session: AuriUIScreenSession
    let onSurfaceAction: (AuriUISurfaceAction) -> Void

    public init(
        sections: [AuriUISection],
        session: AuriUIScreenSession,
        onSurfaceAction: @escaping (AuriUISurfaceAction) -> Void
    ) {
        self.sections = sections
        self.session = session
        self.onSurfaceAction = onSurfaceAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: VisualDesign.sectionSpacing) {
            ForEach(entries) { entry in
                AuriUISectionView(
                    section: entry.section,
                    session: session,
                    onSurfaceAction: onSurfaceAction
                )
                .visualEntrance(index: min(entry.index, 6), isEnabled: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        // Markdown images must not bypass the host's image resolver. Images
        // belong in AuriUI's image components, which use that resolver.
        .markdownImageProvider(AuriUIMarkdownImagesDisabled())
        .markdownInlineImageProvider(AuriUIMarkdownImagesDisabled())
        .environment(\.openURL, OpenURLAction { url in
            guard session.canPerform(.url(.direct(url))) else { return .discarded }
            onSurfaceAction(.openURL(url))
            return .handled
        })
    }

    /// Container identity is based on semantic content that stays stable as
    /// streaming appends children. It avoids coupling SwiftUI identity to an
    /// array offset while still allowing two same-kind sections.
    private var entries: [Entry] {
        var occurrences: [String: Int] = [:]
        return sections.enumerated().map { index, section in
            let seed = section.visualIdentitySeed
            let occurrence = occurrences[seed, default: 0]
            occurrences[seed] = occurrence + 1
            return Entry(
                id: "\(session.id)|\(seed)|\(occurrence)",
                index: index,
                section: section
            )
        }
    }

    private struct Entry: Identifiable {
        let id: String
        let index: Int
        let section: AuriUISection
    }
}

@available(iOS 17.0, macOS 14.0, *)
private extension AuriUISection {
    var visualIdentitySeed: String {
        switch self {
        case .intro:
            return "intro"
        case .header(_, let title, _):
            return "header|\(title)"
        case .hero(let imageQuery, let caption):
            return "hero|\(imageQuery ?? caption ?? "")"
        case .button(let button):
            return "button|\(button.label)"
        case .row(let title, let items):
            return "row|\(title ?? items.first?.title ?? "")"
        case .posters(let title, let items):
            return "posters|\(title ?? items.first?.title ?? "")"
        case .menu(let title, let items):
            return "menu|\(title ?? items.first?.title ?? "")"
        case .grid(let title, let items):
            return "grid|\(title ?? items.first?.title ?? "")"
        case .cards(let cards):
            return "cards|\(cards.first?.title ?? "")"
        case .steps(let title, let items):
            return "steps|\(title ?? items.first?.title ?? "")"
        case .facts(let title, let items):
            return "facts|\(title ?? items.first?.title ?? "")"
        case .bullets(let title, _, _):
            return "bullets|\(title ?? "")"
        case .stats(let title, let items):
            return "stats|\(title ?? items.first?.label ?? "")"
        case .expand(let title, let items):
            return "expand|\(title ?? items.first?.title ?? "")"
        case .chips(let chips):
            return "chips|\(chips.first?.label ?? "")"
        case .sources:
            return "sources"
        case .list(let list):
            return "list|\(list.title ?? list.items.first?.selectionValue ?? "")"
        case .receipt(let title, let lines):
            return "receipt|\(title ?? lines.first?.label ?? "")"
        case .compare(let comparison):
            return "compare|\(comparison.columns.first?.title ?? "")"
        case .chart(let chart):
            return "chart|\(chart.title)"
        case .table(let table):
            return "table|\(table.title ?? table.columns.first?.title ?? "")"
        case .form(let form):
            return "form|\(form.id)"
        case .tabs(let tabs):
            return "tabs|\(tabs.first?.title ?? "")"
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct AuriUISectionView: View {
    let section: AuriUISection
    let session: AuriUIScreenSession
    let onSurfaceAction: (AuriUISurfaceAction) -> Void

    var body: some View {
        switch section {
        case .intro(let text):
            VisualIntroView(text: text)
        case .header(let emoji, let title, let subtitle):
            VisualHeaderView(emoji: emoji, title: title, subtitle: subtitle)
        case .hero(let imageQuery, let caption):
            AuriUIHeroView(imageQuery: imageQuery, caption: caption, session: session)
        case .button(let button):
            AuriUIScreenButtonView(button: button, session: session) { action in
                dispatch(action)
            }
        case .row(let title, let items):
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    VisualSectionTitle(title: title)
                }
                VisualMediaRowView(items: tileItems(items), onAction: bridge)
            }
        case .posters(let title, let items):
            AuriUIPostersView(
                title: title,
                items: items,
                session: session,
                onAction: { action in
                    dispatch(session.interpolated(action))
                },
                onOpenPage: { pageTitle in
                    session.presentPage(titled: pageTitle)
                }
            )
        case .menu(let title, let items):
            AuriUIMenuView(title: title, items: items, session: session) { action in
                dispatch(session.interpolated(action))
            }
        case .grid(let title, let items):
            VisualGridView(title: title, items: tileItems(items), onAction: bridge)
        case .cards(let cards):
            VisualEntityCardsView(cards: cardItems(cards), onAction: bridge)
        case .steps(let title, let items):
            VisualStepsCarouselView(
                title: title,
                items: items.map { VisualItem(emoji: $0.emoji, title: $0.title, detail: $0.detail) },
                messageID: session.id,
                sectionID: "steps"
            )
        case .facts(let title, let items):
            AuriUIFactsView(title: title, items: items)
        case .bullets(let title, let checklist, let items):
            VisualBulletsView(title: title, isChecklist: checklist, items: items.map { VisualItem(text: $0) })
        case .stats(_, let items):
            VisualStatsRowView(items: items.map {
                VisualItem(value: $0.value, label: $0.label, trend: $0.trend.flatMap { VisualTrend(rawValue: $0.rawValue) })
            })
        case .expand(_, let items):
            VisualExpandablesView(items: items.map { VisualItem(title: $0.title, body: $0.body) })
        case .chips(let chips):
            VisualChipsView(
                items: chips.filter { session.canPerform(.send(prompt: $0.prompt)) }
                    .map { VisualItem(label: $0.label, prompt: $0.prompt) },
                onAction: bridge
            )
        case .sources(let sources):
            VisualSourcesView(
                items: sources.compactMap { source in
                    // References resolve to real URLs or the source drops.
                    guard let url = session.resolveURLString(source.urlString),
                          session.canPerform(.url(.direct(url))) else { return nil }
                    return VisualItem(title: source.title, url: url.absoluteString, domain: Self.hostname(url.absoluteString))
                },
                onAction: bridge
            )
        case .list(let list):
            AuriUIOptionListView(list: list, session: session)
        case .receipt(let title, let lines):
            AuriUIReceiptView(title: title, lines: lines, session: session)
        case .compare(let comparison):
            // Contender headers with a matching detail page open it on tap —
            // a comparison is also the index into its contenders.
            VisualComparisonView(
                columns: comparison.columns.map { column in
                    VisualColumn(
                        imageURL: column.imageQuery.flatMap { session.services.imageURL(query: $0) },
                        title: column.title
                    )
                },
                groups: Self.comparisonGroups(comparison),
                tappableColumns: Set(comparison.columns.indices.filter {
                    session.page(for: comparison.columns[$0].title) != nil
                }),
                onColumnTap: { index in
                    guard comparison.columns.indices.contains(index) else { return }
                    session.presentPage(titled: comparison.columns[index].title)
                }
            )
        case .chart(let chart):
            AuriUIChartView(chart: chart)
        case .table(let table):
            AuriUITableView(table: table)
        case .form(let form):
            AuriUIFormView(form: form, session: session, onAction: dispatch)
        case .tabs(let tabs):
            AuriUITabsSectionView(tabs: tabs, session: session, onSurfaceAction: onSurfaceAction)
        }
    }

    /// Routes VisualActions coming out of reused v1 views into surface
    /// actions, interpolating money/selection placeholders on the way out.
    private func bridge(_ action: VisualAction) {
        switch action {
        case .sendPrompt(let prompt), .composePrompt(let prompt):
            dispatch(.send(prompt: session.interpolate(prompt)))
        case .openURL(let url):
            dispatch(.url(.direct(url)))
        case .navigate(let brief):
            dispatch(.nav(brief: session.interpolate(brief)))
        case .openPage(let title):
            session.presentPage(titled: title)
        }
    }

    private func dispatch(_ action: AuriUIAction) {
        guard session.canPerform(action) else { return }
        switch action {
        case .send(let prompt):
            onSurfaceAction(.sendToChat(prompt: prompt))
        case .nav(let brief):
            onSurfaceAction(.navigate(brief: brief, parentID: session.id))
        case .url(let target):
            // Only real, resolved URLs leave the surface.
            if let url = session.resolveURL(target) {
                onSurfaceAction(.openURL(url))
            }
        case .hostCapability(let id):
            onSurfaceAction(.hostCapability(id: id))
        }
    }

    // MARK: - Adapters (AuriUI → v1 view models)

    private func tileItems(_ tiles: [AuriUITile]) -> [VisualItem] {
        tiles.map { tile in
            VisualItem(
                emoji: tile.emoji,
                imageURL: tile.imageQuery.flatMap { session.services.imageURL(query: $0) },
                fullImageURL: tile.imageQuery.flatMap { session.services.imageURL(query: $0, full: true) },
                title: tile.title,
                subtitle: tile.subtitle,
                caption: tile.caption,
                action: visualAction(tile.action) ?? pageAction(for: tile.title)
            )
        }
    }

    /// Tap default: an actionless tile whose title matches a detail page
    /// opens that page — tiles should always open something.
    private func pageAction(for title: String) -> VisualAction? {
        session.page(for: title) != nil ? .openPage(title) : nil
    }

    private func cardItems(_ cards: [AuriUICard]) -> [VisualCard] {
        cards.map { card in
            VisualCard(
                emoji: card.emoji,
                imageURL: card.imageQuery.flatMap { session.services.imageURL(query: $0) },
                fullImageURL: card.imageQuery.flatMap { session.services.imageURL(query: $0, full: true) },
                title: card.title,
                subtitle: card.subtitle,
                stats: card.stats.map { VisualStat(label: $0.label, value: $0.value) },
                action: visualAction(card.action) ?? pageAction(for: card.title)
            )
        }
    }

    private func visualAction(_ action: AuriUIAction?) -> VisualAction? {
        guard let action, session.canPerform(action) else { return nil }
        switch action {
        case .send(let prompt):
            return .sendPrompt(prompt)
        case .nav(let brief):
            return .navigate(brief)
        case .url(let target):
            return session.resolveURL(target).map { .openURL($0) }
        case .hostCapability:
            // Host actions use the native AuriUI button path. They never
            // enter adapters shared with model-authored visual documents.
            return nil
        }
    }

    static func comparisonGroups(_ comparison: AuriUIComparison) -> [VisualComparisonGroup] {
        comparison.groups.map { group in
            VisualComparisonGroup(
                emoji: nil,
                title: group.title,
                rows: group.rows.map { row in
                    VisualComparisonRow(
                        label: row.label,
                        values: row.values.enumerated().map { index, value in
                            let winner = row.winner
                            let verdict: VisualVerdict
                            if winner == index + 1 {
                                verdict = .good
                            } else if winner != nil, comparison.columns.count == 2 {
                                verdict = .bad
                            } else {
                                verdict = .neutral
                            }
                            return VisualComparisonValue(
                                text: value,
                                verdict: verdict,
                                note: row.notes.indices.contains(index) ? row.notes[index] : nil
                            )
                        }
                    )
                }
            )
        }
    }

    static func hostname(_ urlString: String) -> String? {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "")
    }
}

// MARK: - Tabs

@available(iOS 17.0, macOS 14.0, *)
struct AuriUITabsSectionView: View {
    let tabs: [AuriUITab]
    let session: AuriUIScreenSession
    let onSurfaceAction: (AuriUISurfaceAction) -> Void

    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Section"), selection: $selectedTab) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Text(tab.title).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tabs.indices.contains(selectedTab) {
                AuriUISectionsColumn(
                    sections: tabs[selectedTab].sections,
                    session: session,
                    onSurfaceAction: onSurfaceAction
                )
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIMarkdownImagesDisabled: ImageProvider, InlineImageProvider {
    func makeImage(url: URL?) -> some View {
        EmptyView()
    }

    func image(with url: URL, label: String) async throws -> Image {
        throw URLError(.unsupportedURL)
    }
}
#endif
