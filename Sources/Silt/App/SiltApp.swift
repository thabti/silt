import SwiftUI

@main
struct SiltApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 940, minHeight: 660)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { model.scan() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("What Silt never touches", destination: URL(string: "https://support.apple.com/guide/mac-help/free-up-storage-space-sm3d6a2f4a7b/mac")!)
            }
        }
    }
}
