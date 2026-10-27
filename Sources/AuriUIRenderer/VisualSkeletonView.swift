#if os(iOS) || os(macOS)
//
//  VisualSkeletonView.swift
//  Auri
//
//  In-flight state for a visual answer: a live status pill over shimmering
//  placeholder blocks. As sections stream in (partial document), real content
//  progressively replaces the skeleton.
//

import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct VisualSkeletonView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VisualSkeletonBlock(height: 110)
                VisualSkeletonBlock(height: 110)
            }
            VisualSkeletonBlock(height: 14, widthFraction: 0.55)
            VisualSkeletonBlock(height: 88)
            VisualSkeletonBlock(height: 14, widthFraction: 0.8)
            VisualSkeletonBlock(height: 14, widthFraction: 0.65)
        }
        .accessibilityHidden(true)
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct VisualSkeletonBlock: View {
    var height: CGFloat
    var widthFraction: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(height: CGFloat, widthFraction: CGFloat = 1) {
        self.height = height
        self.widthFraction = widthFraction
    }

    public var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                skeletonShape(width: proxy.size.width * widthFraction)
            } else {
                skeletonShape(width: proxy.size.width * widthFraction)
                    .auriUIShimmer()
            }
        }
        .frame(height: height)
    }

    private func skeletonShape(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(12, height / 2), style: .continuous)
            .fill(Color.gray.opacity(0.14))
            .frame(width: width, height: height)
    }
}
#endif
