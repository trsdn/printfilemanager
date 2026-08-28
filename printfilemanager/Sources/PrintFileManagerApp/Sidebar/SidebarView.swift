import AppKit
import PrintFileManagerCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SidebarSection(title: "Library") {
                    VStack(spacing: 4) {
                        ForEach(SmartCollection.allCases) { collection in
                            SidebarCollectionButton(collection: collection)
                        }
                    }
                }

                SidebarSection(title: "Auto Sort Target") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = viewModel.managedFolderURL {
                            Label(url.lastPathComponent, systemImage: "shippingbox")
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("No target folder")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                viewModel.setManagedFolderFromPanel()
                            } label: {
                                Label("Set Target", systemImage: "folder.badge.gearshape")
                            }
                        }
                        .controlSize(.small)

                        if viewModel.selectedRecordCount > 0 {
                            Label("\(viewModel.selectedRecordCount.formatted()) selected", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {

                            Button {
                                viewModel.prepareOrganizationPlan(settings: aiSettings.enrichmentSettings())
                            } label: {
                                Label("Copy Selected", systemImage: "doc.on.doc")
                            }
                            .disabled(viewModel.managedFolderURL == nil || viewModel.selectedRecordCount == 0 || viewModel.isOrganizing)
                            .help("Copy selected files into the managed library")

                            Button {
                                viewModel.prepareMoveOrganizationPlan(settings: aiSettings.enrichmentSettings())
                            } label: {
                                Label("Move Selected", systemImage: "arrowshape.turn.up.right")
                            }
                            .disabled(viewModel.managedFolderURL == nil || viewModel.selectedRecordCount == 0 || viewModel.isOrganizing)
                            .help("Move or re-sort selected files into the managed library")
                        }
                        .controlSize(.small)
                    }
                }

                SidebarSection(title: "Scanned Folders") {
                    if viewModel.snapshot.roots.isEmpty {
                        Text("No folders")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(viewModel.snapshot.roots) { root in
                                FolderRow(root: root)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if viewModel.isScanning || viewModel.isOrganizing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
        }
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

struct SidebarCollectionButton: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let collection: SmartCollection

    var body: some View {
        Button {
            viewModel.select(collection: collection)
        } label: {
            HStack(spacing: 8) {
                Label(collection.title, systemImage: collection.systemImage)
                Spacer()
                Text("\(viewModel.count(for: collection))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            viewModel.selectedRootID == nil && viewModel.selectedCollection == collection ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

struct FolderRow: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let root: LibraryRoot

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.select(root: root)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: root.isAvailable ? "folder" : "folder.badge.questionmark")
                        .foregroundStyle(root.isAvailable ? Color.secondary : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(root.displayName)
                            .lineLimit(1)
                        Text(root.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(viewModel.count(for: root))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                viewModel.selectedRootID == root.id ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .help("Show folder contents")

            Button {
                viewModel.scan(root: root)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .accessibilityLabel("Rescan folder")
            .help("Rescan folder")
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([root.url])
            }
            Button("Rescan Folder") {
                viewModel.scan(root: root)
            }
            Divider()
            Button("Remove from Library", role: .destructive) {
                viewModel.removeRootRequest = root
            }
        }
    }
}
