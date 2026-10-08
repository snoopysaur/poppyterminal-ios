import SwiftUI

@main
struct PoppyTerminalApp: App {
    @State private var store = ServerStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            root
                .environment(store)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if DesignCatalog.isRequested {
            DesignCatalogView()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }
}
