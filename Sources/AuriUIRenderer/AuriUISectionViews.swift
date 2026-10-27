#if os(iOS) || os(macOS)
//
//  AuriUISectionViews.swift
//  Auri
//
//  The generated-surface section views that have no v1 equivalent: hero,
//  selectable option lists, receipts with the client-computed total row, and
//  the screen CTA. Everything money-related reads AuriUISelectionState — the
//  model itemizes, only the client sums.
//

import AuriUI
import SwiftUI

// MARK: - Art direction (screen tint)

/// The model's `tint:` name mapped to a platform color; the flow's accent.
@available(iOS 17.0, macOS 14.0, *)
public enum AuriUITintPalette {
    public static func color(named name: String?) -> Color? {
        switch name {
        case "amber", "orange": return .orange
        case "mint": return .mint
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "violet": return .purple
        case "rose": return .pink
        case "red": return .red
        case "green": return .green
        case "slate": return .gray
        default: return nil
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension EnvironmentValues {
    /// The surface's art-direction accent (screen `tint:`, app accent
    /// fallback). Drives CTAs, selection, badges, and the ambient wash.
    @Entry public var auriUIAccent = Color.accentColor
}

/// The 1px image outline from the design guidelines: pure white in dark
/// mode, pure black in light, both at 10% — never a tinted neutral.
@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIImageOutline: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10),
                    lineWidth: 1
                )
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    func auriUIImageOutline(cornerRadius: CGFloat) -> some View {
        modifier(AuriUIImageOutline(cornerRadius: cornerRadius))
    }
}

// MARK: - Hero

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIHeroView: View {
    let imageQuery: String?
    let caption: String?
    let session: AuriUIScreenSession

    var body: some View {
        VisualRemoteImage(
            imageURL: imageQuery.flatMap { session.services.imageURL(query: $0) },
            emoji: nil,
            height: 210,
            cornerRadius: 24,
            fallbackImageURL: imageQuery.flatMap { session.services.imageURL(query: $0, full: true) }
        )
        .overlay {
            // The streaming-era scrim: content-anchored, so the display
            // title always sits on legible ground regardless of the photo.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.62), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottomLeading) {
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .auriUIImageOutline(cornerRadius: 24)
        .accessibilityLabel(Text(caption ?? ""))
    }
}

// MARK: - Posters (2:3 cover carousel)

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIPostersView: View {
    let title: String?
    let items: [AuriUITile]
    let session: AuriUIScreenSession
    let onAction: (AuriUIAction) -> Void
    var onOpenPage: ((String) -> Void)? = nil

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                VisualSectionTitle(title: title)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.title) { _, tile in
                        posterTile(tile)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func posterTile(_ tile: AuriUITile) -> some View {
        let content = VStack(alignment: .leading, spacing: 7) {
            VisualRemoteImage(
                imageURL: tile.imageQuery.flatMap { session.services.imageURL(query: $0) },
                emoji: tile.emoji,
                height: 177,
                cornerRadius: 14,
                fallbackImageURL: tile.imageQuery.flatMap { session.services.imageURL(query: $0, full: true) }
            )
            .frame(width: 118)
            .auriUIImageOutline(cornerRadius: 14)
            // Layered depth: covers float, they don't sit in card chrome.
            .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            .overlay(alignment: .topLeading) {
                if let badge = tile.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent, in: Capsule())
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                if let caption = tile.caption ?? tile.subtitle {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 118, alignment: .leading)

        if let action = tile.action, session.canPerform(action) {
            Button {
                VisualHaptics.tap()
                onAction(action)
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(tile.title))
        } else if let onOpenPage, session.page(for: tile.title) != nil {
            Button {
                VisualHaptics.tap()
                onOpenPage(tile.title)
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(tile.title))
            .accessibilityHint(Text(String(localized: "Opens details")))
        } else {
            content
        }
    }
}

// MARK: - Detail page sheet

/// A tile's tap-to-open mini interface: the page's sections rendered with
/// the full section library, presented as a sheet with the flow's tint.
@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIPageSheet: View {
    let page: AuriUIPage
    let session: AuriUIScreenSession
    let onSurfaceAction: (AuriUISurfaceAction) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        page: AuriUIPage,
        session: AuriUIScreenSession,
        onSurfaceAction: @escaping (AuriUISurfaceAction) -> Void
    ) {
        self.page = page
        self.session = session.pageSession(for: page)
        self.onSurfaceAction = onSurfaceAction
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AuriUISectionsColumn(
                        sections: session.document.sections,
                        session: session,
                        onSurfaceAction: onSurfaceAction
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .navigationTitle(page.forTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}

// MARK: - Facts (icon-led feature rows)

/// The editorial feature list: emoji lead, bold title, quiet detail. No card
/// chrome — whitespace and alignment do the work.
@available(iOS 17.0, macOS 14.0, *)
struct AuriUIFactsView: View {
    let title: String?
    let items: [AuriUIStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                VisualSectionTitle(title: title)
            }
            ForEach(Array(items.enumerated()), id: \.element.title) { _, fact in
                HStack(alignment: .top, spacing: 12) {
                    VisualEmojiTile(emoji: fact.emoji, size: 38, fontSize: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let detail = fact.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Table (standings / schedules / compact matrices)

/// A neutral data matrix. Unlike `compare`, it does not imply that every
/// column is a contender or that each row needs a winner.
@available(iOS 17.0, macOS 14.0, *)
struct AuriUITableView: View {
    let table: AuriUITable

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = table.title {
                VisualSectionTitle(title: title)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.columns) { column in
                        Text(column.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(column.id == firstColumnID ? .leading : .trailing)
                            .gridColumnAlignment(column.id == firstColumnID ? .leading : .trailing)
                    }
                }
                .padding(.vertical, 10)

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                ForEach(table.rows) { row in
                    GridRow {
                        ForEach(row.cells) { cell in
                            Text(cell.text.isEmpty ? "—" : cell.text)
                                .font(.subheadline.weight(cell.id == firstColumnID ? .medium : .regular))
                                .monospacedDigit()
                                .lineLimit(2)
                                .multilineTextAlignment(cell.id == firstColumnID ? .leading : .trailing)
                        }
                    }
                    .padding(.vertical, 10)
                    .background {
                        if row.isHighlighted {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accent.opacity(0.12))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(row.values.joined(separator: ", ")))

                    Divider()
                        .opacity(row.id == table.rows.last?.id ? 0 : 1)
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .visualCard(treatment: .grouped)
        }
    }

    private var firstColumnID: String? { table.columns.first?.id }
}

// MARK: - Menu (commerce rows)

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIMenuView: View {
    let title: String?
    let items: [AuriUIMenuItem]
    let session: AuriUIScreenSession
    let onAction: (AuriUIAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                VisualSectionTitle(title: title)
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.title) { index, item in
                    AuriUIMenuRow(item: item, session: session, onAction: onAction)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .visualCard(treatment: .grouped)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIMenuRow: View {
    let item: AuriUIMenuItem
    let session: AuriUIScreenSession
    let onAction: (AuriUIAction) -> Void

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        if let action = item.action, session.canPerform(action) {
            Button {
                VisualHaptics.tap()
                onAction(action)
            } label: {
                rowContent(isActionable: true)
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(item.title))
        } else {
            rowContent(isActionable: false)
        }
    }

    private func rowContent(isActionable: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                if let badge = item.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.13), in: Capsule())
                }
                if let detail = item.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let price = item.price {
                    Text(session.selection.formattedPrice(price, locale: Locale.current))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.imageQuery != nil || item.emoji != nil {
                VisualRemoteImage(
                    imageURL: item.imageQuery.flatMap { session.services.imageURL(query: $0) },
                    emoji: item.emoji,
                    height: 88,
                    cornerRadius: 16
                )
                .frame(width: 88)
                .auriUIImageOutline(cornerRadius: 16)
                .overlay(alignment: .bottomTrailing) {
                    if isActionable {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(accent, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            .offset(x: 6, y: 6)
                    }
                }
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

// MARK: - Option list (pick / multi)

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIOptionListView: View {
    let list: AuriUIOptionList
    let session: AuriUIScreenSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = list.title {
                VisualSectionTitle(title: title)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.items.enumerated()), id: \.element.selectionValue) { index, option in
                    AuriUIOptionRow(
                        option: option,
                        isSelected: isSelected(option),
                        isPick: isPick,
                        priceTag: session.selection.priceTag(for: option.price, locale: Locale.current)
                    ) {
                        VisualHaptics.selection()
                        switch list.mode {
                        case .pick(let group):
                            session.select(group: group, value: option.selectionValue)
                        case .multi:
                            session.toggle(value: option.selectionValue)
                        }
                    }
                    if index < list.items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .visualCard(treatment: .grouped)
        }
    }

    private var isPick: Bool {
        if case .pick = list.mode { return true }
        return false
    }

    private func isSelected(_ option: AuriUIOption) -> Bool {
        switch list.mode {
        case .pick(let group):
            return session.selection.isSelected(group: group, value: option.selectionValue)
        case .multi:
            return session.selection.isToggled(value: option.selectionValue)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIOptionRow: View {
    let option: AuriUIOption
    let isSelected: Bool
    let isPick: Bool
    let priceTag: String
    let onTap: () -> Void

    @Environment(\.auriUIAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VisualEmojiTile(emoji: option.emoji, size: 36, fontSize: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(priceTag)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(option.price == 0 ? Color.secondary : accent)
                Image(systemName: selectionSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.35))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background {
                // Concentric with the 16pt card: 4pt inset → 12pt radius.
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.10))
                        .padding(4)
                        .transition(.opacity)
                }
            }
            .animation(VisualMotion.standard(reduceMotion: reduceMotion), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(VisualPressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(Text("\(option.title), \(priceTag)"))
        .accessibilityIdentifier("auriui.option.\(option.selectionValue)")
    }

    private var selectionSymbol: String {
        if isPick {
            return isSelected ? "checkmark.circle.fill" : "circle"
        }
        return isSelected ? "checkmark.square.fill" : "square"
    }
}

// MARK: - Receipt

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIReceiptView: View {
    let title: String?
    let lines: [AuriUIReceiptLine]
    let session: AuriUIScreenSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                VisualSectionTitle(title: title)
            }
            VStack(spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(session.selection.formattedPrice(line.price, locale: Locale.current))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                    }
                }
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // The one and only sum, computed client-side. Digits
                    // roll rather than snap when selections change it.
                    Text(session.selection.formattedTotal(locale: Locale.current))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .animation(VisualMotion.standard(reduceMotion: reduceMotion), value: session.selection)
                }
            }
            .padding(14)
            .visualCard(treatment: .grouped)
        }
    }

    @Environment(\.auriUIAccent) private var accent
}

// MARK: - Screen CTA

@available(iOS 17.0, macOS 14.0, *)
struct AuriUIScreenButtonView: View {
    let button: AuriUIButton
    let session: AuriUIScreenSession
    let onAction: (AuriUIAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A button that cannot act does not render — no dead ends. URL
        // targets must resolve (an r-id missing from DATA yields nothing).
        if let action = button.action, isActionable(action) {
            Button {
                guard button.state == .enabled else { return }
                VisualHaptics.tap()
                onAction(session.interpolated(action))
            } label: {
                HStack(spacing: 8) {
                    if button.state == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(button.isPrimary ? .white : accent)
                    }
                    Text(session.interpolate(button.label))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText())
                        .lineLimit(1)
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(button.isPrimary ? Color.white : accent)
                .background(
                    button.isPrimary ? accent : accent.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(
                    color: button.isPrimary ? accent.opacity(0.22) : .clear,
                    radius: 9, y: 4
                )
                .shadow(
                    color: button.isPrimary ? accent.opacity(0.12) : .clear,
                    radius: 3, y: 1
                )
                .animation(VisualMotion.standard(reduceMotion: reduceMotion), value: session.selection)
            }
            .buttonStyle(VisualPressableButtonStyle())
            .disabled(button.state != .enabled)
            .accessibilityValue(
                button.state == .loading
                    ? Text(String(localized: "In progress"))
                    : Text("")
            )
            .accessibilityIdentifier("auri.ui.\(action.capabilityID)")
        }
    }

    @Environment(\.auriUIAccent) private var accent

    private func isActionable(_ action: AuriUIAction) -> Bool {
        session.canPerform(action)
    }
}

// MARK: - Composing footer

/// Shimmer shown under already-rendered sections while the stream is live.
@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIComposingFooter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        Group {
            if reduceMotion {
                footerShape
            } else {
                footerShape
                    .auriUIShimmer()
            }
        }
        .accessibilityLabel(Text("Generating…"))
    }

    private var footerShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.gray.opacity(0.14))
            .frame(height: 44)
    }
}
#endif
