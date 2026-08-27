import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("3MF Quick Look")
                        .font(.title2.weight(.semibold))
                    Text("Finder previews for Bambu and MakerWorld 3MF files")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("Press Space on a supported .3mf file in Finder to preview it.", systemImage: "space")
                Label("Use icon view or gallery view to see generated thumbnails.", systemImage: "square.grid.2x2")
                Label("Preview generation stays local and read-only.", systemImage: "lock")
            }
            .labelStyle(.titleAndIcon)

            Spacer()
        }
        .padding(28)
    }
}

#Preview {
    ContentView()
}
