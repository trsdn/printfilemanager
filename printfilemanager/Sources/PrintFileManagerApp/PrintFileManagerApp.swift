import SwiftUI

@main
struct PrintFileManagerApp: App {
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var aiSettings = AISettingsStore()

    var body: some Scene {
        Window("Print File Manager", id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(aiSettings)
                .task {
                    await viewModel.load()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandMenu("Library") {
                Button("Add Folder...") {
                    viewModel.addFolderFromPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Rescan All") {
                    viewModel.rescanAllRoots()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(aiSettings)
        }
    }
}
