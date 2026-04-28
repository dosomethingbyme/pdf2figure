import SwiftUI

@main
struct FigraApp: App {
    var body: some Scene {
        WindowGroup("Figra") {
            FigraAppView()
        }
        .windowStyle(.titleBar)
    }
}
