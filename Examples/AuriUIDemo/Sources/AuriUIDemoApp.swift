import SwiftUI

@main
struct AuriUIDemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                DemoCatalogView(title: "Gallery", samples: DemoSample.gallery)
                    .tabItem { Label("Gallery", systemImage: "square.grid.2x2") }

                DemoCatalogView(title: "Interactive", samples: DemoSample.interactive)
                    .tabItem { Label("Interactive", systemImage: "hand.tap") }

                DemoStreamingView()
                    .tabItem { Label("Streaming", systemImage: "text.line.first.and.arrowtriangle.forward") }

                DemoLiveView()
                    .tabItem { Label("Live", systemImage: "sparkles") }
            }
            .tint(.indigo)
        }
    }
}
