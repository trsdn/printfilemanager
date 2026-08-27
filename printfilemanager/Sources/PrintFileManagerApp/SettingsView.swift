import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var aiSettings: AISettingsStore

    var body: some View {
        Form {
            Section {
                TextField("Endpoint", text: $aiSettings.endpointURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key", text: $aiSettings.apiKey)
                    .textFieldStyle(.roundedBorder)
                Toggle("Include preview image when enriching", isOn: $aiSettings.includeThumbnail)

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
                Text("AI enrichment is optional. Base URLs like /v1 are expanded to /v1/models and /v1/chat/completions. Leave the API key empty for local endpoints that do not require authentication; non-empty keys are stored in Keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560)
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