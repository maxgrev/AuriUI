#if os(iOS) || os(macOS)
//
//  VisualInteractiveViews.swift
//  Auri
//
//  Interactive Visual mode sections: tabs, expandables, follow-up chips,
//  action buttons, and source attribution.
//

import AuriUI
import SwiftUI
import MarkdownUI

@available(iOS 17.0, macOS 14.0, *)
struct VisualTabsView: View {
    let tabs: [VisualTab]
    let messageID: String
    var isInteractionEnabled: Bool = true
    let onAction: (VisualAction) -> Void

    @State private var selectedIndex = 0
    @Environment(\.auriUIAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabPicker
            if tabs.indices.contains(selectedIndex) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tabs[selectedIndex].sections) { section in
                        VisualSectionView(
                            section: section,
                            messageID: messageID,
                            isInteractionEnabled: isInteractionEnabled,
                            onAction: onAction
                        )
                    }
                }
                .id(selectedIndex)
                .transition(.opacity)
            }
        }
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button {
                        guard selectedIndex != index else { return }
                        VisualHaptics.selection()
                        withAnimation(VisualMotion.standard(reduceMotion: reduceMotion)) {
                            selectedIndex = index
                        }
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(selectedIndex == index ? .semibold : .regular))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                selectedIndex == index
                                    ? AnyShapeStyle(accent.opacity(0.15))
                                    : AnyShapeStyle(Color.primary.opacity(0.055)),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        selectedIndex == index
                                            ? accent.opacity(0.40)
                                            : Color.primary.opacity(0.10),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(VisualPressableButtonStyle())
                    .accessibilityAddTraits(selectedIndex == index ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualExpandablesView: View {
    let items: [VisualItem]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VisualExpandableRow(item: item)
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct VisualExpandableRow: View {
    let item: VisualItem
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                VisualHaptics.selection()
                withAnimation(VisualMotion.standard(reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(item.title ?? "")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])

            if isExpanded {
                Markdown(item.body ?? "")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .visualCard(cornerRadius: 14, treatment: .grouped)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualChipsView: View {
    let items: [VisualItem]
    // Kept for API symmetry; taps during streaming are inert upstream, so
    // chips render full-strength immediately — no muted state to snap out of.
    var isInteractionEnabled: Bool = true
    let onAction: (VisualAction) -> Void

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    VisualHaptics.tap()
                    if let prompt = item.prompt {
                        onAction(.sendPrompt(prompt))
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                            .foregroundStyle(accent)
                        Text(item.label ?? "")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.primary)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                    }
                }
                .buttonStyle(VisualPressableButtonStyle())
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualButtonsView: View {
    let items: [VisualItem]
    // Kept for API symmetry; see VisualChipsView.
    var isInteractionEnabled: Bool = true
    let onAction: (VisualAction) -> Void

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if let action = item.action {
                    Button {
                        VisualHaptics.tap()
                        onAction(action)
                    } label: {
                        HStack(spacing: 5) {
                            if case .openURL = action {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.semibold))
                            }
                            Text(item.label ?? "")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(.primary)
                        .background(accent.opacity(0.14), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(accent.opacity(0.34), lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(VisualPressableButtonStyle())
                }
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualSourcesView: View {
    let items: [VisualItem]
    let onAction: (VisualAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Sources"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                    if let urlString = item.url, let url = URL(string: urlString) {
                        Button {
                            VisualHaptics.tap()
                            onAction(.openURL(url))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 8))
                                Text(item.domain ?? url.host()?.replacingOccurrences(of: "www.", with: "") ?? urlString)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                        }
                        .buttonStyle(VisualPressableButtonStyle())
                        .accessibilityLabel(Text(item.title ?? item.domain ?? ""))
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}

// Minimal wrapping flow layout for chips/buttons/sources.
@available(iOS 17.0, macOS 14.0, *)
public struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
#endif
