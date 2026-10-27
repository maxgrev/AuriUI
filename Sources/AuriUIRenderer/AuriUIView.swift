#if os(iOS) || os(macOS)
import AuriUI
import SwiftUI

/// Renders an interactive document inside the host's layout.
///
/// Put this view in a `ScrollView` for long documents. Keep the session in the
/// host's state so form values and selections survive view updates. Actions
/// leave the renderer through `onAction`; the host decides how to handle them.
/// Partial sections remain interactive while the document streams. If the
/// stream fails, the partial document stays visible with its controls disabled.
@available(iOS 17.0, macOS 14.0, *)
public struct AuriUIView: View {
    private let session: AuriUIScreenSession
    private let accentColor: Color
    private let onAction: (AuriUISurfaceAction) -> Void

    public init(
        session: AuriUIScreenSession,
        accentColor: Color = .accentColor,
        onAction: @escaping (AuriUISurfaceAction) -> Void = { _ in }
    ) {
        self.session = session
        self.accentColor = accentColor
        self.onAction = onAction
    }

    private var accent: Color {
        AuriUITintPalette.color(named: session.document.screen?.tint) ?? accentColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AuriUISectionsColumn(
                sections: session.document.sections,
                session: session,
                onSurfaceAction: onAction
            )
            .disabled(isIncomplete)

            switch session.phase {
            case .composing:
                if session.document.sections.isEmpty {
                    VisualSkeletonView()
                } else {
                    AuriUIComposingFooter()
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again", systemImage: "arrow.clockwise") {
                        session.retry()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("auriui.retry")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            case .ready:
                EmptyView()
            }
        }
        .environment(\.auriUIAccent, accent)
        .tint(accent)
        .sheet(
            item: Binding(
                get: { session.presentedPage },
                set: { session.presentedPage = $0 }
            ),
            onDismiss: session.dismissPresentedPage
        ) { presented in
            AuriUIPageSheet(page: presented.page, session: session) { action in
                session.presentedPage = nil
                onAction(action)
            }
            .environment(\.auriUIAccent, accent)
            .tint(accent)
        }
        .task { session.start() }
        .onAppear { session.becameVisible() }
        .onDisappear {
            session.cancel()
            session.dismissPresentedPage()
        }
    }

    private var isIncomplete: Bool {
        if case .failed = session.phase { return true }
        return false
    }
}
#endif
