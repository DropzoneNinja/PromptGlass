import SwiftUI

@main
struct PromptGlassApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Reasonable default dimensions; the user's last size is auto-saved by SwiftUI.
        .defaultSize(width: 960, height: 640)
        // Wire in the app-level menu commands (File > New Script, Session menu).
        .commands {
            AppCommands()
        }
    }
}
