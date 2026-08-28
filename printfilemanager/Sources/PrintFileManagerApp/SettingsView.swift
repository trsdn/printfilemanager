import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var aiSettings: AISettingsStore
    @EnvironmentObject private var viewModel: LibraryViewModel

    @State private var isConfirmingDelete = false
    @State private var deleteResult: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI enrichment", isOn: $aiSettings.enrichmentEnabled)
                TextField("Endpoint", text: $aiSettings.endpointURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!aiSettings.enrichmentEnabled)
                SecureField("API key", text: $aiSettings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!aiSettings.enrichmentEnabled)
                Toggle("Include preview image when enriching", isOn: $aiSettings.includeThumbnail)
                    .disabled(!aiSettings.enrichmentEnabled)

                HStack(spacing: 8) {
                    Button {
                        aiSettings.loadModels()
                    } label: {
                        Label("Load Models", systemImage: "arrow.down.circle")
                    }
                    .disabled(aiSettings.isLoadingModels)

                    if aiSettings.isLoadingModels {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(aiSettings.modelLoadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if aiSettings.availableModels.isEmpty {
                    TextField("Model", text: $aiSettings.model)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Selected model", selection: $aiSettings.model) {
                        ForEach(aiSettings.offeredModels) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .disabled(aiSettings.offeredModels.isEmpty)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Offered Models")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(aiSettings.availableModels) { model in
                                    Toggle(isOn: enabledBinding(for: model.name)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.name)
                                            if let owner = model.owner, !owner.isEmpty {
                                                Text(owner)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 140, maxHeight: 260)
                    }
                }
            } header: {
                Label("AI Enrichment", systemImage: "sparkles")
                    .font(.headline)
            } footer: {
                Text("""
                    Disabled by default. Nothing is sent anywhere until you enable it. \
                    When enabled, enriching a file sends its name, folder path, extracted metadata \
                    and — if the toggle above is on — its preview image to the endpoint you configure. \
                    Base URLs like /v1 are expanded to /v1/models and /v1/chat/completions. \
                    The endpoint must use https, except for local servers. \
                    Leave the API key empty for local endpoints that do not require authentication; \
                    non-empty keys are stored in Keychain.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable web source lookup", isOn: $aiSettings.sourceLookupEnabled)
            } header: {
                Label("Source Lookup", systemImage: "magnifyingglass")
                    .font(.headline)
            } footer: {
                Text("""
                    Disabled by default and independent of AI enrichment. When enabled, the Find \
                    button sends this model's project or file name to a web search engine and \
                    fetches the matching page from MakerWorld, Printables, Thingiverse or Cults to \
                    read its title, description and last update.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Library index", value: viewModel.storageLocations.index.path)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button {
                        exportLibrary()
                    } label: {
                        Label("Export Library…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([viewModel.storageLocations.index])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete All Data…", systemImage: "trash")
                    }
                }

                if let deleteResult {
                    Text(deleteResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Your Data", systemImage: "internaldrive")
                    .font(.headline)
            } footer: {
                Text("""
                    Everything this app knows lives in the index above and a preview store beside \
                    it, both on this Mac only. Export writes that index as plain JSON. Deleting \
                    removes the index and every stored preview; your own model files are never \
                    touched.
                    """)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: AppIdentity.versionDescription)
                if let repositoryURL = AppIdentity.repositoryURL {
                    Link("Source code", destination: repositoryURL)
                }
                if let issueTrackerURL = AppIdentity.issueTrackerURL {
                    Link("Report an issue", destination: issueTrackerURL)
                }
            } header: {
                Label("About", systemImage: "info.circle")
                    .font(.headline)
            } footer: {
                Text(AppIdentity.copyright)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
        .confirmationDialog(
            "Delete the library index and all stored previews?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                let removed = viewModel.deleteAllLibraryData()
                deleteResult = "Removed \(removed.formatted()) indexed files. Your model files were not touched."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your own model files on disk are not affected.")
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "print-file-manager-library.json"
        panel.allowedContentTypes = [.json]
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.exportLibrary(to: url)
    }

    private func enabledBinding(for modelName: String) -> Binding<Bool> {
        Binding(
            get: { aiSettings.enabledModelNames.contains(modelName) },
            set: { aiSettings.setModel(modelName, enabled: $0) }
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(AISettingsStore())
}
