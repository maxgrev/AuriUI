#if os(iOS) || os(macOS)
//
//  VisualCardsViews.swift
//  Auri
//
//  Image-forward Visual mode sections: entity cards, media rows, and item
//  grids. Cards with actions dispatch through onAction (tap → follow-up
//  prompt or link).
//

import AuriUI
import SwiftUI

// A tile's embedded detail page, presented as a native sheet — instant,
// because the orchestrator composed it alongside the main answer.
@available(iOS 17.0, macOS 14.0, *)
struct VisualDetailPayload: Identifiable {
    let id: String
    let emoji: String?
    let imageURL: URL?
    /// Tried when `imageURL` (the original-resolution photo) fails — usually
    /// the tile's CDN thumbnail, which is near-guaranteed to load.
    var fallbackImageURL: URL? = nil
    let title: String
    let subtitle: String?
    let sections: [ChatVisualSection]
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualDetailSheet: View {
    let payload: VisualDetailPayload
    let messageID: String
    let onAction: (VisualAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VisualDesign.sectionSpacing) {
                    if payload.imageURL != nil {
                        VisualRemoteImage(imageURL: payload.imageURL, emoji: payload.emoji, height: 190, cornerRadius: 18, fallbackImageURL: payload.fallbackImageURL)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payload.title)
                            .font(.title2.weight(.bold))
                        if let subtitle = payload.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(payload.sections.enumerated()), id: \.element.id) { index, section in
                        VisualSectionView(
                            section: section,
                            messageID: "\(messageID)-\(payload.id)",
                            isInteractionEnabled: true,
                            onAction: onAction
                        )
                        .visualEntrance(index: index)
                    }
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#elseif os(macOS)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 480, idealHeight: 600)
#endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualEntityCardsView: View {
    let cards: [VisualCard]
    var isInteractionEnabled: Bool = true
    let onAction: (VisualAction) -> Void

    @Environment(\.visualDetailsPending) private var detailsPending
    @State private var selectedDetail: VisualDetailPayload?

    var body: some View {
        // Two cards share a row; three or more wrap into a 2-column grid so
        // the bubble never outgrows a phone screen.
        Group {
            if cards.count <= 2 {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        entityCard(card, index: index)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(cards.prefix(4).enumerated()), id: \.offset) { index, card in
                        entityCard(card, index: index)
                    }
                }
            }
        }
        .sheet(item: $selectedDetail) { payload in
            VisualDetailSheet(payload: payload, messageID: payload.id, onAction: { action in
                selectedDetail = nil
                onAction(action)
            })
        }
    }

    @ViewBuilder
    private func entityCard(_ card: VisualCard, index: Int) -> some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            VisualRemoteImage(imageURL: card.imageURL, emoji: card.emoji, height: 92, fallbackImageURL: card.fullImageURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            if let stats = card.stats, !stats.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(stats.prefix(3).enumerated()), id: \.offset) { _, stat in
                        HStack(spacing: 4) {
                            Text(stat.label)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(stat.value)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .visualCard(treatment: .elevated)

        // Tiles have one job on tap: open their detail page. No page (rare —
        // the worker guarantees pages for tiles) means a static tile; the
        // only other tap behavior allowed is a plain link. Pages are joined
        // into the card at document decode, so this is plain value data that
        // re-renders through ordinary diffing when the merge lands.
        if let detailSections = card.detailSections, !detailSections.isEmpty {
            Button {
                VisualHaptics.tap()
                selectedDetail = VisualDetailPayload(
                    id: "card-\(index)",
                    emoji: card.emoji,
                    imageURL: card.fullImageURL ?? card.imageURL,
                    fallbackImageURL: card.imageURL,
                    title: card.title ?? "",
                    subtitle: card.subtitle,
                    sections: detailSections
                )
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(card.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens details")))
        } else if case .navigate(let brief)? = card.action, isInteractionEnabled, !detailsPending {
            // Generated surfaces: the card opens its next screen.
            Button {
                VisualHaptics.tap()
                onAction(.navigate(brief))
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(card.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens screen")))
        } else if case .openPage(let pageTitle)? = card.action, isInteractionEnabled, !detailsPending {
            // Generated surfaces: the card opens its AuriUI detail page.
            Button {
                VisualHaptics.tap()
                onAction(.openPage(pageTitle))
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(card.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens details")))
        } else if case .openURL(let url)? = card.action, isInteractionEnabled, !detailsPending {
            Button {
                VisualHaptics.tap()
                onAction(.openURL(url))
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(card.title ?? ""))
        } else {
            content
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualMediaRowView: View {
    let items: [VisualItem]
    var isInteractionEnabled: Bool = true
    let onAction: (VisualAction) -> Void

    @Environment(\.visualDetailsPending) private var detailsPending
    @State private var selectedDetail: VisualDetailPayload?

    /// Identity follows the generated item instead of its current array
    /// position. This matters when a chat row is reconstructed or a streamed
    /// section grows: SwiftUI must not reuse Yosemite's button as Monterey's.
    private struct Entry: Identifiable {
        let id: String
        let index: Int
        let item: VisualItem
    }

    private var entries: [Entry] {
        var occurrences: [String: Int] = [:]
        return items.enumerated().map { index, item in
            let parts = [
                item.title,
                item.imageURL?.absoluteString,
                item.fullImageURL?.absoluteString,
                item.caption,
                item.subtitle,
            ].compactMap { $0 }
            let base = parts.isEmpty ? "visual-item" : parts.joined(separator: "|")
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return Entry(id: "\(base)#\(occurrence)", index: index, item: item)
        }
    }

    var body: some View {
        Group {
            // Desktop wraps the gallery into a grid so every tile is visible
            // without horizontal mouse-scrolling; iOS keeps the swipe row.
            if VisualLayout.expandsCarousels {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 10, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(entries) { entry in
                        mediaCard(entry.item, index: entry.index)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(entries) { entry in
                            mediaCard(entry.item, index: entry.index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
        .sheet(item: $selectedDetail) { payload in
            VisualDetailSheet(payload: payload, messageID: payload.id, onAction: { action in
                selectedDetail = nil
                onAction(action)
            })
        }
    }

    @ViewBuilder
    private func mediaCard(_ item: VisualItem, index: Int) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            VisualRemoteImage(imageURL: item.imageURL, emoji: item.emoji, height: 150, cornerRadius: 10, fallbackImageURL: item.fullImageURL)
                .frame(width: 110)
                .auriUIImageOutline(cornerRadius: 10)
                .shadow(color: .black.opacity(0.10), radius: 7, y: 3)
            Text(item.title ?? "")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let caption = item.caption ?? item.subtitle {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 110, alignment: .leading)

        // Tiles have one job on tap: open their detail page (or follow a
        // plain link). Never the composer. Pages are joined into the item at
        // document decode, so this is plain value data.
        if let detailSections = item.detailSections, !detailSections.isEmpty {
            Button {
                VisualHaptics.tap()
                selectedDetail = VisualDetailPayload(
                    id: "media-\(index)",
                    emoji: item.emoji,
                    imageURL: item.fullImageURL ?? item.imageURL,
                    fallbackImageURL: item.imageURL,
                    title: item.title ?? "",
                    subtitle: item.caption ?? item.subtitle,
                    sections: detailSections
                )
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(item.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens details")))
        } else if case .navigate(let brief)? = item.action, isInteractionEnabled, !detailsPending {
            // Generated surfaces: the tile opens its next screen.
            Button {
                VisualHaptics.tap()
                onAction(.navigate(brief))
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(item.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens screen")))
        } else if case .openPage(let pageTitle)? = item.action, isInteractionEnabled, !detailsPending {
            // Generated surfaces: the tile opens its AuriUI detail page.
            Button {
                VisualHaptics.tap()
                onAction(.openPage(pageTitle))
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(item.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens details")))
        } else if case .openURL(let url)? = item.action, isInteractionEnabled, !detailsPending {
            Button {
                VisualHaptics.tap()
                onAction(.openURL(url))
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(item.title ?? ""))
        } else {
            content
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualGridView: View {
    let title: String?
    let items: [VisualItem]
    /// Generated surfaces pass this so grid tiles with actions are tappable;
    /// chat answers leave it nil and the grid stays static.
    var onAction: ((VisualAction) -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                VisualSectionTitle(title: title)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    gridTile(item)
                }
            }
        }
    }

    @ViewBuilder
    private func gridTile(_ item: VisualItem) -> some View {
        let content = VStack(spacing: 6) {
            if let imageURL = item.imageURL {
                VisualRemoteImage(imageURL: imageURL, emoji: item.emoji, height: 56, cornerRadius: 12)
                    .frame(width: 56)
            } else {
                VisualEmojiTile(emoji: item.emoji, size: 56, fontSize: 30)
            }
            VStack(spacing: 1) {
                Text(item.title ?? "")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .visualCard(cornerRadius: 14, treatment: .subtle)

        if let onAction, let action = item.action {
            Button {
                VisualHaptics.tap()
                onAction(action)
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(item.title ?? ""))
        } else {
            content
        }
    }
}
#endif
