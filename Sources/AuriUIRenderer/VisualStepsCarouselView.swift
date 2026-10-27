#if os(iOS) || os(macOS)
//
//  VisualStepsCarouselView.swift
//  Auri
//
//  Swipeable numbered step carousel with a progress rail. Steps are
//  checkable; completion state is session-scoped (VisualInteractionStore),
//  not persisted.
//

import AuriUI
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct VisualStepsCarouselView: View {
    let title: String?
    let items: [VisualItem]
    let messageID: String
    let sectionID: String

    @ObservedObject private var store = VisualInteractionStore.shared
    @Environment(\.auriUIAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                VisualSectionTitle(title: title)
            }
            // Desktop shows the full sequence as a vertical numbered list — the
            // natural recipe layout — so the cooking flow reads top-to-bottom
            // and every step is visible. iOS keeps the swipeable carousel with
            // its progress rail. (A wrapping grid was wrong here: it broke the
            // step order and detached the cards from the numbered rail.)
            if VisualLayout.expandsCarousels {
                stepsList
            } else {
                progressRail
                carousel
            }
        }
    }

    // A vertical stepper: numbered nodes on a connecting spine that fills with
    // accent as steps are completed, so the cooking sequence reads as a flow
    // (the horizontal rail's "cleverness", translated to a full-height list).
    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VerticalStepRow(
                    item: item,
                    index: index,
                    isLast: index == items.count - 1,
                    isChecked: store.isStepChecked(messageID: stepKey, index: index),
                    previousChecked: index > 0 && store.isStepChecked(messageID: stepKey, index: index - 1)
                ) {
                    VisualHaptics.selection()
                    withAnimation(VisualMotion.standard(reduceMotion: reduceMotion)) {
                        store.toggleStep(messageID: stepKey, index: index)
                    }
                }
            }
        }
    }

    // Numbered rail with the step emoji milestones, echoing the reference
    // design (1 — 2 — 3 … with icons).
    private var progressRail: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { index, item in
                VStack(spacing: 3) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(store.isStepChecked(messageID: stepKey, index: index) ? .bold : .regular))
                        .foregroundStyle(store.isStepChecked(messageID: stepKey, index: index) ? accent : .secondary)
                    Text(item.emoji ?? "•")
                        .font(.footnote)
                        .opacity(0.85)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                if index < min(items.count, 8) - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    stepCard(item, index: index)
                }
            }
            .padding(.vertical, 2)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private var stepKey: String {
        "\(messageID)-\(sectionID)"
    }

    private func stepCard(_ item: VisualItem, index: Int) -> some View {
        let isChecked = store.isStepChecked(messageID: stepKey, index: index)

        return Button {
            VisualHaptics.selection()
            withAnimation(VisualMotion.standard(reduceMotion: reduceMotion)) {
                store.toggleStep(messageID: stepKey, index: index)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VisualEmojiTile(emoji: item.emoji, size: 40, fontSize: 22)
                    Spacer()
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isChecked ? accent : Color.secondary.opacity(0.5))
                }
                Text(item.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail = item.detail ?? item.text {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 200, height: 150, alignment: .topLeading)
            .visualCard(treatment: .grouped)
            .opacity(isChecked ? 0.65 : 1)
        }
        .buttonStyle(VisualPressableButtonStyle())
        .accessibilityLabel(Text("\(index + 1). \(item.title ?? item.detail ?? "")"))
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

// One row of the desktop vertical stepper: a numbered node on a connecting
// spine plus the step card. Its own view so it can hold hover state.
@available(iOS 17.0, macOS 14.0, *)
private struct VerticalStepRow: View {
    let item: VisualItem
    let index: Int
    let isLast: Bool
    let isChecked: Bool
    let previousChecked: Bool
    let onTap: () -> Void

    @State private var isHovering = false
    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                spine
                card
            }
        }
        .buttonStyle(VisualPressableButtonStyle())
        .accessibilityLabel(Text("Step \(index + 1). \(item.title ?? item.detail ?? "")"))
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    // Node with a connector above AND below it, so the node sits centered on
    // the card (the card's symmetric vertical padding matches the flexible
    // connectors) while the spine stays continuous. A segment fills accent
    // once its upper step is done — hence `previousChecked` for the top half.
    private var spine: some View {
        VStack(spacing: 0) {
            connector(isAccented: previousChecked)
                .opacity(index > 0 ? 1 : 0)
            node
            connector(isAccented: isChecked)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 30)
    }

    private func connector(isAccented: Bool) -> some View {
        Rectangle()
            .fill(isAccented ? accent.opacity(0.55) : Color.secondary.opacity(0.18))
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    private var node: some View {
        ZStack {
            Circle()
                .fill(isChecked ? accent : accent.opacity(0.12))
            Circle()
                .strokeBorder(accent.opacity(isChecked ? 0 : 0.35), lineWidth: 1.5)
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 10) {
            VisualEmojiTile(emoji: item.emoji, size: 34, fontSize: 19)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                if let detail = item.detail ?? item.text {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .visualCard(cornerRadius: 14, treatment: .grouped)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.045 : 0))
        }
        .opacity(isChecked ? 0.6 : 1)
        // Symmetric padding centers the card in the row so the node (centered
        // in the spine) lines up with the card's middle; also forms the 12pt
        // gap between cards that the connectors bridge.
        .padding(.vertical, 6)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

#endif
