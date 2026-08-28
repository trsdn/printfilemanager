import PrintFileManagerCore
import SwiftUI

struct OrganizationPlanSheet: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let plan: OrganizationPlan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: isMovePlan ? "arrowshape.turn.up.right" : "doc.on.doc")
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(planTitle)
                        .font(.title3.weight(.semibold))
                    Text(planSummary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Target")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(plan.targetRootURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            List(plan.actions.prefix(80)) { action in
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.destinationURL.lastPathComponent)
                        .font(.body.weight(.medium))
                    Text(relativeDestinationPath(action.destinationURL))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !action.reason.isEmpty {
                        Text(action.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(action.sourceURL.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 260)

            if plan.actions.count > 80 {
                Text("Showing the first 80 planned actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button {
                    viewModel.executeOrganizationPlan(plan)
                    dismiss()
                } label: {
                    Label(confirmTitle, systemImage: isMovePlan ? "arrowshape.turn.up.right" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan.actions.isEmpty || viewModel.isOrganizing)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
    }

    private var isMovePlan: Bool {
        plan.actions.contains { $0.kind == .move }
    }

    private var operationTitle: String {
        isMovePlan ? "Move" : "Copy"
    }

    private var planTitle: String {
        if isMovePlan, isReSortPlan {
            return "Re-sort Managed Files"
        }
        return isMovePlan ? "Move into Managed Library" : "Copy into Managed Library"
    }

    private var planSummary: String {
        let fileWord = plan.actions.count == 1 ? "file" : "files"
        let actionText = "\(plan.actions.count) \(fileWord) will be \(isMovePlan ? "moved" : "copied")."
        let safetyText = isMovePlan ? "Original files change location." : "Original files stay where they are."
        let skippedText = plan.skippedCount == 1 ? "1 file is already in place or skipped." : "\(plan.skippedCount) files are already in place or skipped."
        return "\(actionText) \(safetyText) \(skippedText)"
    }

    private var confirmTitle: String {
        isMovePlan ? "Move Files" : "Copy Files"
    }

    private var isReSortPlan: Bool {
        !plan.actions.isEmpty && plan.actions.allSatisfy { action in
            let targetPath = plan.targetRootURL.standardizedFileURL.path
            let sourcePath = action.sourceURL.standardizedFileURL.path
            return sourcePath == targetPath || sourcePath.hasPrefix(targetPath + "/")
        }
    }

    private func relativeDestinationPath(_ url: URL) -> String {
        let targetPath = plan.targetRootURL.standardizedFileURL.path
        let destinationPath = url.standardizedFileURL.path
        guard destinationPath.hasPrefix(targetPath) else { return destinationPath }
        let startIndex = destinationPath.index(destinationPath.startIndex, offsetBy: targetPath.count)
        return String(destinationPath[startIndex...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// Shown after an organization batch finishes. It is the only place the user learns which files
/// actually moved, which were skipped and which failed — and the only route to undo.

struct OrganizationReportSheet: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let report: OrganizationExecutionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(report.kind == .move ? "Move Complete" : "Copy Complete")
                    .font(.title3.weight(.semibold))
                Text(report.summary)
                    .font(.callout)
                    .foregroundStyle(report.failedCount > 0 ? .orange : .secondary)
            }

            if !report.failures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These files were not \(report.kind == .move ? "moved" : "copied")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.failures) { outcome in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(outcome.action.sourceURL.lastPathComponent)
                                        .font(.callout)
                                    if case .failed(let message) = outcome.result {
                                        Text(message)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
            }

            HStack {
                if report.isUndoable {
                    Button(report.kind == .move ? "Undo Move" : "Undo Copy") {
                        viewModel.undoLastOrganization()
                    }
                    .disabled(viewModel.isOrganizing)
                    .help(report.kind == .move
                          ? "Move the files back to where they came from."
                          : "Remove the copies from the managed library. Your originals are untouched.")
                }

                Spacer()

                Button("Done") {
                    viewModel.dismissOrganizationReport()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }
}
