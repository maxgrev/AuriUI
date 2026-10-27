#if os(iOS) || os(macOS)
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
private struct AuriUIShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width)
                        .phaseAnimator([false, true]) { gradient, phase in
                            gradient.offset(x: phase ? geometry.size.width : -geometry.size.width)
                        } animation: { _ in
                            .linear(duration: 1.6)
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    func auriUIShimmer() -> some View {
        modifier(AuriUIShimmer())
    }
}
#endif
