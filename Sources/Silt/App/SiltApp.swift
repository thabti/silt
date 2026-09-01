import SwiftUI

@main
struct SiltApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Silt", id: "main") {
            RootView(model: model)
                .frame(minWidth: 880, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("What Silt never touches", destination: URL(string: "https://support.apple.com/guide/mac-help/free-up-storage-space-sm3d6a2f4a7b/mac")!)
            }
            CommandMenu("View") {
                Button("Overview") { model.route = .overview }.keyboardShortcut("1", modifiers: .command)
                Button("Large files") { model.route = .files }.keyboardShortcut("2", modifiers: .command)
                Button("Build artifacts") { model.route = .artifacts }.keyboardShortcut("3", modifiers: .command)
            }
        }

        Settings { SettingsView() }
    }
}
