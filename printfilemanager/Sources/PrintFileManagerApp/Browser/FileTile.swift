import AppKit
import PrintFileManagerCore
import SwiftUI

struct FileTile: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    @EnvironmentObject private var aiSettings: AISettingsStore
    let record: PrintFileRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.45))
                ThumbnailView(data: viewModel.thumbnail(for: record))
                    .padding(8)
            }
            .frame(height: 132)

            VStack(alignment: .leading, spacing: 4) {
                // Reserving both lines is what keeps the grid straight. Without it a one-line
                // title makes a shorter tile than a two-line one, every row takes the height of
                // its tallest tile, and the rest float at different offsets inside it -- which
                // reads as a broken layout rather than as varying title lengths.
                Text(record.projectName ?? record.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                Text(record.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                // Badges live in their own clipping group. Left in the same row as the buttons,
                // a file with several badges pushes the row's minimum width past the grid column
                // and the tile overflows into its neighbour -- which is what made the grid look
                // broken after a resize. Extra badges are now cut off instead.
                HStack(spacing: 6) {
                    if !activeReviewReasons.isEmpty {
                        TileStatusBadge(
                            title: activeReviewReasons.map(\.title).joined(separator: ", "),
                            systemImage: "exclamationmark.triangle.fill",
                            value: "\(activeReviewReasons.count)",
                            tint: .orange
                        )
                    }
                    TileStatusBadge(
                        title: record.previewStatus == .available ? "Preview available" : "No preview available",
                        systemImage: record.previewStatus == .available ? "checkmark.circle.fill" : "photo",
                        tint: record.previewStatus == .available ? .green : .secondary
                    )
                    if let printability = record.printability {
                        TileStatusBadge(
                            title: printability.title,
                            systemImage: "checklist.checked",
                            tint: .blue
                        )
                    }
                    if !record.userTags.isEmpty {
                        TileStatusBadge(
                            title: "\(record.userTags.count) user tags",
                            systemImage: "tag.fill",
                            value: "\(record.userTags.count)",
                            tint: .secondary
                        )
                    }
                }
                // `minWidth: 0` is what actually lets this compress. `.clipped()` alone only
                // affects drawing: without a frame that may be narrower than its contents, four
                // badges at 24pt each still demand 114pt, which together with three fixed
                // buttons exceeds the grid's 176pt column and pushes the tile into its
                // neighbour.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()

                Button {
                    viewModel.prepareMovePlan(for: record, settings: aiSettings.enrichmentSettings())
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Move to managed library")
                .disabled(viewModel.managedFolderURL == nil)
                .help("Move to managed folder")

                Button {
                    viewModel.openInBambuStudio(record: record)
                } label: {
                    Image(systemName: "cube")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Open in Bambu Studio")
                .help("Open in Bambu Studio")

                Button(role: .destructive) {
                    viewModel.requestDelete(record: record)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Move to Trash")
                .help("Move to Trash")
            }
            .frame(height: 28)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
        }
        // Combined into one element with named actions rather than leaving the three icon
        // buttons unreachable inside it: VoiceOver could otherwise neither read the tile as a
        // unit nor operate its actions.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Select this file")
        .accessibilityAction(named: "Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([record.url])
        }
        .accessibilityAction(named: "Open") {
            viewModel.openInDefaultApp(record: record)
        }
        .accessibilityAction(named: "Move to Trash") {
            viewModel.requestDelete(record: record)
        }
        .contextMenu {
            Button {
                viewModel.openInDefaultApp(record: record)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([record.url])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                viewModel.openInBambuStudio(record: record)
            } label: {
                Label("Open in Bambu Studio", systemImage: "cube")
            }

            Button {
                viewModel.prepareCopyPlan(for: record, settings: aiSettings.enrichmentSettings())
            } label: {
                Label("Copy to Managed Folder", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.managedFolderURL == nil)

            Button {
                viewModel.prepareMovePlan(for: record, settings: aiSettings.enrichmentSettings())
            } label: {
                Label("Move to Managed Folder", systemImage: "arrowshape.turn.up.right")
            }
            .disabled(viewModel.managedFolderURL == nil)

            if !viewModel.reviewReasons(for: record).isEmpty {
                Button {
                    if viewModel.isReviewDismissed(for: record) {
                        viewModel.reopenReview(record)
                    } else {
                        viewModel.markReviewed(record)
                    }
                } label: {
                    Label(viewModel.isReviewDismissed(for: record) ? "Reopen Review" : "Mark Reviewed", systemImage: viewModel.isReviewDismissed(for: record) ? "arrow.uturn.backward" : "checkmark.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                viewModel.requestDelete(record: record)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }

    private var activeReviewReasons: [ReviewReason] {
        guard !viewModel.isReviewDismissed(for: record) else { return [] }
        return viewModel.reviewReasons(for: record)
    }

    /// One spoken sentence describing the tile, so VoiceOver conveys what the visual layout
    /// conveys at a glance instead of reading a pile of disconnected labels.
    private var accessibilityDescription: String {
        var parts = [record.projectName ?? record.fileName]
        if let printability = record.printability?.title {
            parts.append(printability)
        }
        if !record.userTags.isEmpty {
            parts.append("\(record.userTags.count) tags")
        }
        if !activeReviewReasons.isEmpty {
            parts.append("needs review: \(activeReviewReasons.map(\.title).joined(separator: ", "))")
        }
        if record.previewStatus != .available {
            parts.append("no preview")
        }
        return parts.joined(separator: ", ")
    }
}

struct ThumbnailView: View {
    let data: Data?

    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "cube.transparent")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

struct TileStatusBadge: View {
    let title: String
    let systemImage: String
    var value: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            if let value {
                Text(value)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
            }
        }
            .font(.caption)
            .foregroundStyle(tint)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, value == nil ? 0 : 6)
            .background(.quaternary.opacity(0.35), in: Capsule())
            .help(title)
            .accessibilityLabel(title)
    }
}
