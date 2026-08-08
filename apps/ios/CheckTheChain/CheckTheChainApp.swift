import SwiftUI

@main
struct CheckTheChainApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.load() }
                .tint(Palette.ink)
        }
    }
}
