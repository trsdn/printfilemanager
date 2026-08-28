import AppKit
import PrintFileManagerCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore

    var body: some View {
        VStack(spacing: 0) {
            if let lockout = viewModel.persistenceLockout {
                PersistenceLockoutBanner(lockout: lockout)
            }

            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } content: {
                LibraryBrowserView()
                    .navigationSplitViewColumnWidth(min: 520, ideal: 720)
            } detail: {
                FileInspectorView(record: viewModel.selectedRecord)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let record = viewModel.selectedRecord {
                    Button {
                        viewModel.openInDefaultApp(record: record)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }

                    Button {
                        viewModel.openInBambuStudio(record: record)
                    } label: {
                        Label("Bambu Studio", systemImage: "cube")
                    }

                    Button {
                        viewModel.prepareMovePlan(for: record, settings: aiSettings.enrichmentSettings())
                    } label: {
                        Label("Move to Managed", systemImage: "arrowshape.turn.up.right")
                    }
                    .disabled(viewModel.managedFolderURL == nil)

                    Button(role: .destructive) {
                        viewModel.requestDelete(record: record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Button {
                    viewModel.addFolderFromPanel()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    viewModel.rescanAllRoots()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.snapshot.roots.isEmpty || viewModel.isScanning)
            }
        }
        .sheet(item: $viewModel.organizationPlan) { plan in
            OrganizationPlanSheet(plan: plan)
                .environmentObject(viewModel)
        }
        .sheet(item: $viewModel.lastOrganizationReport) { report in
            OrganizationReportSheet(report: report)
                .environmentObject(viewModel)
        }
        .alert("Move File to Trash?", isPresented: deleteAlertBinding, presenting: viewModel.deleteCandidate) { record in
            Button("Cancel", role: .cancel) {
                viewModel.deleteCandidate = nil
            }
            Button("Move to Trash", role: .destructive) {
                viewModel.moveDeleteCandidateToTrash()
            }
        } message: { record in
            Text("This will move \(record.fileName) to the macOS Trash and remove it from the library index.")
        }
        .alert("Remove Folder from Library?", isPresented: removeRootAlertBinding, presenting: viewModel.removeRootRequest) { root in
            Button("Cancel", role: .cancel) {
                viewModel.removeRootRequest = nil
            }
            Button("Remove", role: .destructive) {
                viewModel.removeRoot(root)
            }
        } message: { root in
            Text("\(root.displayName) will no longer be scanned and its indexed files, tags and notes will be removed from the library. The files on disk are not touched.")
        }
    }

    private var removeRootAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.removeRootRequest != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.removeRootRequest = nil
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deleteCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.deleteCandidate = nil
                }
            }
        )
    }
}

/// Shown when the library index could not be read. Writes are blocked in that state, so the user
/// has to be told loudly and given a way out — otherwise everything they do is silently discarded.

struct PersistenceLockoutBanner: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @State private var isConfirmingFreshLibrary = false

    let lockout: LibraryViewModel.PersistenceLockout

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your library index could not be read — changes are not being saved.")
                    .font(.callout.weight(.semibold))
                Text(lockout.quarantinedFileURL == nil
                     ? lockout.reason
                     : "\(lockout.reason) The unreadable file has been kept so nothing is lost.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)

            Spacer(minLength: 8)

            if let quarantinedFileURL = lockout.quarantinedFileURL {
                Button("Reveal Saved Copy") {
                    NSWorkspace.shared.activateFileViewerSelecting([quarantinedFileURL])
                }
            }

            Button("Start a Fresh Library") {
                isConfirmingFreshLibrary = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red)
        .confirmationDialog(
            "Start a fresh library?",
            isPresented: $isConfirmingFreshLibrary,
            titleVisibility: .visible
        ) {
            Button("Start Fresh", role: .destructive) {
                viewModel.startFreshLibraryAfterLoadFailure()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your folders, tags and notes will be re-created from scratch. Your .3mf files are never touched, and the unreadable index is kept on disk.")
        }
    }
}
