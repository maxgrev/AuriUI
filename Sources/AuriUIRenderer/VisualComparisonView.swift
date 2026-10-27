#if os(iOS) || os(macOS)
//
//  VisualComparisonView.swift
//  Auri
//
//  Entity comparison (2–3 contenders) as one continuous grid card:
//  contender photos on the header row, grouped metric rows aligned under
//  them, per-cell verdict badges (the Monogram-style green/red callouts).
//  Contender headers with a matching detail page open it on tap.
//

import AuriUI
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct VisualComparisonView: View {
    let columns: [VisualColumn]
    let groups: [VisualComparisonGroup]
    /// Indices into `columns` whose header opens a detail page on tap.
    var tappableColumns: Set<Int> = []
    var onColumnTap: ((Int) -> Void)? = nil

    private var visibleColumns: [VisualColumn] { Array(columns.prefix(3)) }

    var body: some View {
        // One card, one column system: headers and value cells share the
        // same equal-width thirds and insets, so everything lines up.
        VStack(spacing: 0) {
            columnsHeader
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if group.title != nil || group.emoji != nil {
                    HStack(spacing: 6) {
                        if let emoji = group.emoji {
                            Text(emoji)
                                .accessibilityHidden(true)
                        }
                        Text(group.title ?? "")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                ForEach(Array(group.rows.enumerated()), id: \.offset) { rowIndex, row in
                    if rowIndex > 0 {
                        Divider()
                            .opacity(0.5)
                    }
                    comparisonRow(row)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .visualCard(treatment: .grouped)
        .accessibilityElement(children: .contain)
    }

    private var columnsHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(visibleColumns.enumerated()), id: \.offset) { index, column in
                columnHeader(column, index: index)
            }
        }
    }

    @ViewBuilder
    private func columnHeader(_ column: VisualColumn, index: Int) -> some View {
        // Fixed image and title heights keep 1- and 2-line names even.
        let content = VStack(spacing: 6) {
            if column.imageURL != nil {
                VisualRemoteImage(imageURL: column.imageURL, emoji: column.emoji, height: 74, cornerRadius: 14)
                    .auriUIImageOutline(cornerRadius: 14)
            } else {
                VisualEmojiTile(emoji: column.emoji, size: 44)
            }
            Text(column.title ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 34, alignment: .top)
        }
        .frame(maxWidth: .infinity)

        if let onColumnTap, tappableColumns.contains(index) {
            Button {
                VisualHaptics.tap()
                onColumnTap(index)
            } label: {
                content
            }
            .buttonStyle(VisualPressableButtonStyle())
            .accessibilityLabel(Text(column.title ?? ""))
            .accessibilityHint(Text(String(localized: "Opens details")))
        } else {
            content
        }
    }

    private func comparisonRow(_ row: VisualComparisonRow) -> some View {
        VStack(spacing: 6) {
            Text(row.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<visibleColumns.count, id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .frame(height: 26)
                            .opacity(0.5)
                    }
                    comparisonCell(index < row.values.count ? row.values[index] : nil)
                }
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func comparisonCell(_ value: VisualComparisonValue?) -> some View {
        // Parsers pad missing trailing values with "" — render those as the
        // same em dash as an absent cell.
        let text = value?.text ?? ""
        VStack(spacing: 4) {
            Text(text.isEmpty ? "—" : text)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .multilineTextAlignment(.center)
            if let value, !text.isEmpty {
                VisualVerdictBadge(verdict: value.verdict, note: value.note)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
