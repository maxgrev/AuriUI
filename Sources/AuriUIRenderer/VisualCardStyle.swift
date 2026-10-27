#if os(iOS) || os(macOS)
//
//  VisualCardStyle.swift
//  Auri
//
//  Shared design tokens for Visual mode components: the card surface, verdict
//  badges, staggered entrance animation, emoji tiles, and remote images with
//  emoji fallback.
//

import AuriUI
import ImageIO
import SwiftUI

#if os(iOS)
import UIKit
private typealias VisualPlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias VisualPlatformImage = NSImage
#endif

// MARK: - Design system

@available(iOS 17.0, macOS 14.0, *)
enum VisualDesign {
    static let sectionSpacing: CGFloat = 22
    static let contentSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 18
}

@available(iOS 17.0, macOS 14.0, *)
enum VisualCardTreatment: Equatable {
    /// Image-forward or otherwise important content that should lift slightly.
    case elevated
    /// Related rows and dense data that should read as one inset group.
    case grouped
    /// Compact supporting content such as statistics and utility tiles.
    case subtle
}

@available(iOS 17.0, macOS 14.0, *)
enum VisualMotion {
    static func standard(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 1.0)
    }
}

// MARK: - Card surface

@available(iOS 17.0, macOS 14.0, *)
struct VisualCardModifier: ViewModifier {
    var cornerRadius: CGFloat = VisualDesign.cardCornerRadius
    var treatment: VisualCardTreatment = .grouped

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(fillStyle, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.75)
            }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
    }

    private var fillStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(
                Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.055)
            )
        }

        switch treatment {
        case .elevated:
            return AnyShapeStyle(.regularMaterial)
        case .grouped:
            return AnyShapeStyle(.thinMaterial)
        case .subtle:
            return AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.035))
        }
    }

    private var borderColor: Color {
        let base = colorScheme == .dark ? Color.white : Color.black
        let opacity: Double
        if colorSchemeContrast == .increased {
            opacity = colorScheme == .dark ? 0.30 : 0.22
        } else {
            opacity = colorScheme == .dark ? 0.12 : 0.08
        }
        return base.opacity(opacity)
    }

    private var shadowColor: Color {
        guard treatment != .subtle else { return .clear }
        return Color.black.opacity(treatment == .elevated ? 0.14 : 0.07)
    }

    private var shadowRadius: CGFloat {
        treatment == .elevated ? 12 : 5
    }

    private var shadowOffset: CGFloat {
        treatment == .elevated ? 4 : 1
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    func visualCard(
        cornerRadius: CGFloat = VisualDesign.cardCornerRadius,
        treatment: VisualCardTreatment = .grouped
    ) -> some View {
        modifier(VisualCardModifier(cornerRadius: cornerRadius, treatment: treatment))
    }

    func visualEntrance(index: Int, isEnabled: Bool = true) -> some View {
        modifier(VisualEntranceModifier(index: index, isEnabled: isEnabled))
    }
}

// MARK: - Entrance

// Staggered spring entrance, adapted from the generated-asset entrance in
// MessageView. Disabled (`isEnabled: false`) for content that was already
// visible while streaming, so the final render doesn't replay animations.
@available(iOS 17.0, macOS 14.0, *)
struct VisualEntranceModifier: ViewModifier {
    let index: Int
    var isEnabled: Bool = true
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared || reduceMotion ? 1.0 : 0.985)
                .offset(y: hasAppeared || reduceMotion ? 0 : 8)
                .animation(
                    VisualMotion.standard(reduceMotion: reduceMotion)
                        .delay(reduceMotion ? 0 : Double(min(index, 3)) * 0.025),
                    value: hasAppeared
                )
                .onAppear {
                    guard !hasAppeared else { return }
                    hasAppeared = true
                }
        } else {
            content
        }
    }
}

// MARK: - Verdict badge

@available(iOS 17.0, macOS 14.0, *)
struct VisualVerdictBadge: View {
    let verdict: VisualVerdict
    let note: String?

    var body: some View {
        if verdict != .neutral || note != nil {
            HStack(spacing: 3) {
                if verdict != .neutral {
                    Image(systemName: verdict == .good ? "checkmark" : "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                if let note {
                    Text(note)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.85)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var color: Color {
        switch verdict {
        case .good: return .green
        case .bad: return .red
        case .neutral: return .secondary
        }
    }
}

// MARK: - Emoji tile & remote image

@available(iOS 17.0, macOS 14.0, *)
struct VisualEmojiTile: View {
    let emoji: String?
    var size: CGFloat = 44
    var fontSize: CGFloat = 26

    @Environment(\.auriUIAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(colorScheme == .dark ? 0.18 : 0.12), accent.opacity(0.045)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(emoji ?? "✨")
                    .font(.system(size: fontSize))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }
}

/// Remote image with graceful emoji fallback: shows a shimmering placeholder
/// while loading and the emoji tile when the URL is missing or fails.
@available(iOS 17.0, macOS 14.0, *)
struct VisualRemoteImage: View {
    let imageURL: URL?
    let emoji: String?
    var height: CGFloat = 96
    var cornerRadius: CGFloat = 12
    /// Tried when `imageURL` fails to load (e.g. thumbnail primary, original
    /// as backup) before giving up and showing the emoji tile.
    var fallbackImageURL: URL? = nil

    @Environment(\.auriUIAccent) private var accent

    var body: some View {
        // The image lives in an overlay so its intrinsic size can never
        // influence layout — scaledToFill inside a fixed-height frame would
        // otherwise report a width wider than proposed (photo aspect ratio ×
        // height) and inflate the whole message past the screen edge.
        Rectangle()
            .fill(Color.clear)
            .overlay {
                if let imageURL {
                    remoteImage(imageURL) {
                        if let fallbackImageURL, fallbackImageURL != imageURL {
                            remoteImage(fallbackImageURL) {
                                emojiFallback
                            }
                        } else {
                            emojiFallback
                        }
                    }
                } else {
                    emojiFallback
                }
            }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Clipping hides a fill image's overflow but does not constrain its
        // hit or accessibility bounds inside a button.
        .contentShape(.interaction, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func remoteImage<Failure: View>(
        _ url: URL,
        @ViewBuilder onFailure: @escaping () -> Failure
    ) -> some View {
        VisualCachedRemoteImage(url: url, onFailure: onFailure)
    }

    private struct VisualCachedRemoteImage<Failure: View>: View {
        let url: URL
        let onFailure: () -> Failure

        @State private var image: VisualPlatformImage?
        @State private var failed = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(url: URL, @ViewBuilder onFailure: @escaping () -> Failure) {
            self.url = url
            self.onFailure = onFailure
        }

        var body: some View {
            Group {
                if let image {
                    platformImage(image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else if failed {
                    onFailure()
                } else {
                    if reduceMotion {
                        Rectangle()
                            .fill(Color.gray.opacity(0.14))
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.14))
                            .auriUIShimmer()
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: image != nil)
            .task(id: url) {
                image = nil
                failed = false
                do {
                    let data = try await VisualImageCache.shared.data(for: url)
                    try Task.checkCancellation()
                    guard let decoded = await VisualImageDecoder.decode(data) else {
                        failed = true
                        return
                    }
                    try Task.checkCancellation()
                    #if os(iOS)
                    image = UIImage(cgImage: decoded)
                    #elseif os(macOS)
                    image = NSImage(
                        cgImage: decoded,
                        size: NSSize(width: decoded.width, height: decoded.height)
                    )
                    #endif
                } catch is CancellationError {
                    // Scrolling a tile offscreen cancels its view task. A
                    // later appearance can still use the shared cache.
                } catch {
                    failed = true
                }
            }
        }

        private func platformImage(_ image: VisualPlatformImage) -> Image {
            #if os(iOS)
            Image(uiImage: image)
            #elseif os(macOS)
            Image(nsImage: image)
            #endif
        }
    }

    private var emojiFallback: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.18), accent.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: height * 0.36))
                } else {
                    Image(systemName: "photo.fill")
                        .font(.system(size: min(height * 0.26, 38), weight: .medium))
                        .foregroundStyle(accent.opacity(0.72))
                }
            }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private enum VisualImageDecoder {
    /// Remote sources can return multi-megapixel originals even for a small
    /// carousel tile. Decode a bounded thumbnail off the main actor to avoid
    /// scroll hitches and excess resident memory.
    /// CGImage is immutable and Sendable. UIKit/AppKit images are created on
    /// the view's actor after this decode finishes.
    static func decode(_ data: Data) async -> CGImage? {
        await Task.detached(priority: .utility) { () -> CGImage? in
            let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}

// MARK: - Section title

@available(iOS 17.0, macOS 14.0, *)
struct VisualSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Layout

@available(iOS 17.0, macOS 14.0, *)
public enum VisualLayout {
    /// Max readable width of a visual answer's content column.
    public static let columnMaxWidth: CGFloat = 760

    /// Visual answers center their capped column on macOS (so it doesn't hug
    /// the left of a wide window) and fill leading on iOS.
    public static var columnAlignment: Alignment {
        #if os(macOS)
        .center
        #else
        .leading
        #endif
    }

    /// On desktop there's room to lay carousels out in full (wrapping grid)
    /// instead of a clipped horizontal scroll.
    static var expandsCarousels: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

// MARK: - Press feedback

// Subtle tactile scale-on-press for tappable Visual surfaces. 0.96 is the
// tuned value from the design guidelines — anything below 0.95 feels
// exaggerated.
@available(iOS 17.0, macOS 14.0, *)
struct VisualPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // ButtonStyle updates on touch-down, so feedback is immediate.
            // No spring is used here: a tap has no momentum to justify bounce.
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

// MARK: - Haptics

// Feedback generators belong to the renderer and stay isolated to the UI actor.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
enum VisualHaptics {
    #if os(iOS)
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif
    /// Light tap for action taps: chips, buttons, cards/tiles, links.
    @MainActor
    static func tap() {
        #if os(iOS)
        impactGenerator.impactOccurred(intensity: 0.6)
        #endif
    }

    /// Selection feedback for toggles and switches: tabs, steps, expandables.
    @MainActor
    static func selection() {
        #if os(iOS)
        selectionGenerator.selectionChanged()
        #endif
    }
}

// MARK: - Session interaction state (checked steps; not persisted)

@MainActor
@available(iOS 17.0, macOS 14.0, *)
final class VisualInteractionStore: ObservableObject {
    static let shared = VisualInteractionStore()

    @Published private var checkedSteps: [String: Set<Int>] = [:]

    func isStepChecked(messageID: String, index: Int) -> Bool {
        checkedSteps[messageID]?.contains(index) ?? false
    }

    func toggleStep(messageID: String, index: Int) {
        var set = checkedSteps[messageID] ?? []
        if set.contains(index) {
            set.remove(index)
        } else {
            set.insert(index)
        }
        checkedSteps[messageID] = set
    }
}
#endif
