import AuriUI
import AuriUIRenderer
import Foundation

struct DemoSample: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String

    static let gallery: [DemoSample] = [
        .init(id: "inline", title: "Inline document", subtitle: "Embed interactive sections in your own screen", symbol: "rectangle.inset.filled"),
        .init(id: "text", title: "Text and structure", subtitle: "Headings, steps, facts, and actions", symbol: "text.alignleft"),
        .init(id: "media", title: "Media and detail pages", subtitle: "Bundled images, cards, and tap-to-open pages", symbol: "photo.on.rectangle"),
        .init(id: "data", title: "Charts and tables", subtitle: "Line and bar charts, comparisons, and data tables", symbol: "chart.xyaxis.line"),
        .init(id: "tabs", title: "Tabs and expansion", subtitle: "Switch sections and reveal extra detail", symbol: "rectangle.topthird.inset.filled")
    ]

    static let interactive: [DemoSample] = [
        .init(id: "selection", title: "Selection and totals", subtitle: "Choose options and calculate an exact price", symbol: "checklist"),
        .init(id: "form", title: "Validated form", subtitle: "Validate, review, and submit to the host", symbol: "rectangle.and.pencil.and.ellipsis"),
        .init(id: "fields", title: "Every input type", subtitle: "Text, notes, choices, dates, and sliders", symbol: "slider.horizontal.3"),
        .init(id: "host", title: "Host actions", subtitle: "A trusted action registered by this app", symbol: "app.badge.checkmark")
    ]

    @MainActor
    func session() throws -> AuriUIScreenSession {
        if id == "host" {
            return AuriUIScreenSession(
                document: Self.hostDocument,
                services: DemoServices.make()
            )
        }
        return AuriUIScreenSession(answerText: try DemoResources.text(id), services: DemoServices.make())
    }

    static var hostDocument: AuriUIDocument {
        AuriUIDocument(
            screen: .init(id: "host", title: "Host actions", tint: "indigo"),
            sections: [
                .header(emoji: "⭐️", title: "Save a favorite", subtitle: "Your app owns the action"),
                .intro(text: "The host builds this document in Swift and registers the save capability. A model cannot emit this host-only action."),
                .button(.init(label: "Save favorite", isPrimary: true, action: .hostCapability(id: "demo.save"))),
                .button(.init(label: "Unavailable action", action: .hostCapability(id: "demo.unregistered"))),
                .intro(text: "The renderer omits the unregistered action. The result of a supported action appears below.")
            ]
        )
    }
}

enum DemoResources {
    static func text(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "aui", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func imageURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Images")
    }
}

@MainActor
enum DemoServices {
    static func make() -> AuriUIHostServices {
        AuriUIHostServices(
            capabilities: [
                .navigation, .send, .url,
                .init(id: "demo.save", description: "Save a favorite in this app", exposure: .hostOnly)
            ],
            imageURL: { query, _ in DemoResources.imageURL(query) },
            lookupURL: { _ in URL(string: "https://github.com") }
        )
    }
}
