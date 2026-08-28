import PrintFileManagerCore
import SwiftUI

struct TagChip: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Label(title, systemImage: "tag")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

struct ReviewReasonChip: View {
    let reason: ReviewReason
    let isDismissed: Bool

    var body: some View {
        Label(reason.title, systemImage: reason.systemImage)
            .font(.caption)
            .foregroundStyle(isDismissed ? Color.secondary : Color.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

struct SuggestedTagChip: View {
    @EnvironmentObject private var viewModel: LibraryViewModel
    let tag: GeneratedTag
    let record: PrintFileRecord

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.value)
            Button {
                viewModel.acceptGeneratedTag(tag, for: record)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Accept suggested tag")
            .help("Accept tag")

            Button {
                viewModel.rejectGeneratedTag(tag, for: record)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reject suggested tag")
            .help("Reject tag")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

struct DetailSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }

    init(title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Spacer()
                accessory
            }
            content
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

struct SourceURLRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            if let url = URL(string: value), value != "Not set" {
                Link(value, destination: url)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LibraryViewModel())
    .environmentObject(AISettingsStore())
}
