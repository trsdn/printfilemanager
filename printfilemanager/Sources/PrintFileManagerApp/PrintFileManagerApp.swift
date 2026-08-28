import AppKit
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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Saves are coalesced, so the last edits must be forced out before exit.
                    viewModel.flushPendingSave()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(undoTitle) {
                    viewModel.undoLastOrganization()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(viewModel.lastOrganizationReport?.isUndoable ?? false) || viewModel.isOrganizing)
            }

            CommandGroup(after: .pasteboard) {
                Button("Select All") {
                    viewModel.selectAllVisibleRecords()
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(viewModel.filteredRecords.isEmpty)
            }

            CommandMenu("Library") {
                Button("Add Folder...") {
                    viewModel.addFolderFromPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Rescan All") {
                    viewModel.rescanAllRoots()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Reveal in Finder") {
                    if let record = viewModel.selectedRecord {
                        NSWorkspace.shared.activateFileViewerSelecting([record.url])
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.selectedRecord == nil)

                Button("Move to Trash") {
                    if let record = viewModel.selectedRecord {
                        viewModel.requestDelete(record: record)
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedRecord == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(aiSettings)
                .environmentObject(viewModel)
        }
    }

    private var undoTitle: String {
        guard let report = viewModel.lastOrganizationReport, report.isUndoable else {
            return "Undo"
        }
        return report.kind == .move ? "Undo Move Into Library" : "Undo Copy Into Library"
    }
}
