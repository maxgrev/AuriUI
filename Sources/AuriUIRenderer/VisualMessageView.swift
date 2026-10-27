#if os(iOS) || os(macOS)
//
//  VisualMessageView.swift
//  Auri
//
//  Renders an Auri Visual Document as native sections with staggered
//  entrances. Interactive elements dispatch VisualActions upward; the chat
//  surface decides how to send prompts or open links.
//

import AuriUI
import SwiftUI

// True while a finalized message is still waiting for its detail pages to
// stream in — tile taps stay inert for that brief window instead of falling
// back to composer prefill.
@available(iOS 17.0, macOS 14.0, *)
private struct VisualDetailsPendingKey: EnvironmentKey {
    static let defaultValue = false
}

@available(iOS 17.0, macOS 14.0, *)
extension EnvironmentValues {
    public var visualDetailsPending: Bool {
        get { self[VisualDetailsPendingKey.self] }
        set { self[VisualDetailsPendingKey.self] = newValue }
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct VisualMessageView: View {
    let document: ChatVisualDocument
    let messageID: String
    var isInteractionEnabled: Bool = true
    /// Off for a message that just finished streaming — its sections were
    /// already on screen, so replaying entrances would look like a flash.
    var animatesEntrance: Bool = true
    let onAction: (VisualAction) -> Void

    public init(
        document: ChatVisualDocument,
        messageID: String,
        isInteractionEnabled: Bool = true,
        animatesEntrance: Bool = true,
        onAction: @escaping (VisualAction) -> Void
    ) {
        self.document = document
        self.messageID = messageID
        self.isInteractionEnabled = isInteractionEnabled
        self.animatesEntrance = animatesEntrance
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(document.sections.enumerated()), id: \.element.id) { index, section in
                VisualSectionView(
                    section: section,
                    messageID: messageID,
                    isInteractionEnabled: isInteractionEnabled,
                    onAction: onAction
                )
                .visualEntrance(index: index, isEnabled: animatesEntrance)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(document.summary))
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualSectionView: View {
    let section: ChatVisualSection
    let messageID: String
    var isInteractionEnabled: Bool = true
    let onAction: (VisualAction) -> Void

    var body: some View {
        switch section.kind {
        case .intro(let text):
            VisualIntroView(text: text)
        case .header(let emoji, let title, let subtitle):
            VisualHeaderView(emoji: emoji, title: title, subtitle: subtitle)
        case .entityCards(let cards):
            VisualEntityCardsView(cards: cards, isInteractionEnabled: isInteractionEnabled, onAction: onAction)
        case .mediaRow(let items):
            VisualMediaRowView(items: items, isInteractionEnabled: isInteractionEnabled, onAction: onAction)
        case .comparison(let columns, let groups):
            VisualComparisonView(columns: columns, groups: groups)
        case .grid(let title, let items):
            VisualGridView(title: title, items: items)
        case .steps(let title, let items):
            VisualStepsCarouselView(title: title, items: items, messageID: messageID, sectionID: section.id)
        case .bullets(let title, let isChecklist, let items):
            VisualBulletsView(title: title, isChecklist: isChecklist, items: items)
        case .stats(let items):
            VisualStatsRowView(items: items)
        case .tabs(let tabs):
            VisualTabsView(tabs: tabs, messageID: messageID, isInteractionEnabled: isInteractionEnabled, onAction: onAction)
        case .expandables(let items):
            VisualExpandablesView(items: items)
        case .chips(let items):
            VisualChipsView(items: items, isInteractionEnabled: isInteractionEnabled, onAction: onAction)
        case .buttons(let items):
            VisualButtonsView(items: items, isInteractionEnabled: isInteractionEnabled, onAction: onAction)
        case .sources(let items):
            VisualSourcesView(items: items, onAction: onAction)
        }
    }
}
#endif
