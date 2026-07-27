import SwiftUI

@main
struct LocalAnonymizerApp: App {
    var body: some Scene {
        WindowGroup("Локальный анонимизатор") {
            ContentView()
                .frame(minWidth: 900, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 820)
        .windowResizability(.contentMinSize)
    }
}
