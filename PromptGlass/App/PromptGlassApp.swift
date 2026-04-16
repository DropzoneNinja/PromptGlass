import SwiftUI

@main
struct PromptGlassApp: App {

    @State private var aiVM = AIViewModel()

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
        // Share the AI view model with the editor window tree.
        .environment(\.aiViewModel, aiVM)

        // Standard macOS Settings window (Cmd+,).
        Settings {
            TabView {
                AISettingsView(aiVM: aiVM)
                    .tabItem { Label("AI", systemImage: "sparkles") }
            }
            .frame(width: 480, height: 520)
        }

        // Debug window — shows raw request/response from the last AI call.
        Window("AI Debug", id: "ai-debug") {
            AIDebugView(aiVM: aiVM)
        }
        .defaultSize(width: 720, height: 640)
    }
}
