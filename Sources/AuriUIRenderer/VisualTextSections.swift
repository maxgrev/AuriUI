#if os(iOS) || os(macOS)
//
//  VisualTextSections.swift
//  Auri
//
//  Text-centric Visual mode sections: intro paragraph, emoji headers,
//  bullets/checklists, and stat rows.
//

import AuriUI
import SwiftUI
import MarkdownUI

@available(iOS 17.0, macOS 14.0, *)
struct VisualIntroView: View {
    let text: String

    var body: some View {
        Markdown(text)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualHeaderView: View {
    let emoji: String?
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let emoji {
                VisualEmojiTile(emoji: emoji, size: 44, fontSize: 24)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualBulletsView: View {
    let title: String?
    let isChecklist: Bool
    let items: [VisualItem]

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VisualSectionTitle(title: title)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    if isChecklist {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                    } else if let emoji = item.emoji {
                        Text(emoji)
                            .font(.subheadline)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Markdown(item.text ?? "")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct VisualStatsRowView: View {
    let items: [VisualItem]

    // Adaptive grid so four tiles become 2×2 on phone widths instead of
    // forcing the bubble wider than the screen.
    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 220), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Text(item.value ?? "")
                            .font(.title3.bold().monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if let trend = item.trend {
                            Image(systemName: trendSymbol(trend))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(trendColor(trend))
                        }
                    }
                    if let label = item.label {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .visualCard(cornerRadius: 14, treatment: .subtle)
            }
        }
    }

    private func trendSymbol(_ trend: VisualTrend) -> String {
        switch trend {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "minus"
        }
    }

    private func trendColor(_ trend: VisualTrend) -> Color {
        switch trend {
        case .up: return .green
        case .down: return .red
        case .flat: return .secondary
        }
    }
}
#endif
