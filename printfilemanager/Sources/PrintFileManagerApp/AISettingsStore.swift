import Foundation
import PrintFileManagerCore
import Security

@MainActor
final class AISettingsStore: ObservableObject {
    @Published var endpointURL: String {
        didSet { defaults.set(endpointURL, forKey: Keys.endpointURL) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var availableModels: [AIModelInfo] = []

    @Published var enabledModelNames: Set<String> {
        didSet { defaults.set(Array(enabledModelNames).sorted(), forKey: Keys.enabledModelNames) }
    }

    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelLoadStatus = ""

    @Published var includeThumbnail: Bool {
        didSet { defaults.set(includeThumbnail, forKey: Keys.includeThumbnail) }
    }

    /// Master switch for sending anything to the configured AI provider.
    ///
    /// Defaults to `false`: the endpoint and model fields are pre-filled for convenience, so
    /// without an explicit opt-in the app would otherwise appear "configured" and transmit file
    /// names, paths, metadata and preview thumbnails on first use.
    @Published var enrichmentEnabled: Bool {
        didSet { defaults.set(enrichmentEnabled, forKey: Keys.enrichmentEnabled) }
    }

    /// Master switch for the web search used to find a model's original source page.
    ///
    /// Kept separate from `enrichmentEnabled` because it sends project and file names to a search
    /// engine and to arbitrary result pages — a different provider and a different decision.
    @Published var sourceLookupEnabled: Bool {
        didSet { defaults.set(sourceLookupEnabled, forKey: Keys.sourceLookupEnabled) }
    }

    @Published var apiKey: String {
        didSet { persistAPIKey(apiKey) }
    }

    private let defaults: UserDefaults
    private let keychain = APIKeyKeychain()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        endpointURL = defaults.string(forKey: Keys.endpointURL) ?? "https://api.openai.com/v1/chat/completions"
        model = defaults.string(forKey: Keys.model) ?? "gpt-4o-mini"
        includeThumbnail = defaults.object(forKey: Keys.includeThumbnail) as? Bool ?? true
        enrichmentEnabled = defaults.bool(forKey: Keys.enrichmentEnabled)
        sourceLookupEnabled = defaults.bool(forKey: Keys.sourceLookupEnabled)
        enabledModelNames = Set(defaults.stringArray(forKey: Keys.enabledModelNames) ?? [])
        apiKey = defaults.bool(forKey: Keys.apiKeyStored) ? (try? keychain.load()) ?? "" : ""
    }

    var isConfigured: Bool {
        enrichmentSettings() != nil
    }

    func enrichmentSettings() -> AIEnrichmentSettings? {
        guard enrichmentEnabled else {
            return nil
        }

        guard let url = URL(string: endpointURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || url.isLocalhost,
              !selectedModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return AIEnrichmentSettings(
            endpointURL: url,
            apiKey: apiKey,
            model: selectedModelName,
            includeThumbnail: includeThumbnail
        )
    }

    var offeredModels: [AIModelInfo] {
        guard !availableModels.isEmpty else { return [] }
        let enabled = enabledModelNames
        return availableModels.filter { enabled.contains($0.name) }
    }

    var selectedModelName: String {
        if availableModels.isEmpty {
            return model
        }

        if !model.isEmpty, enabledModelNames.contains(model) {
            return model
        }
        return offeredModels.first?.name ?? ""
    }

    func loadModels() {
        guard enrichmentEnabled else {
            modelLoadStatus = "Enable AI enrichment first"
            return
        }

        guard let url = URL(string: endpointURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || url.isLocalhost else {
            modelLoadStatus = "An https endpoint is required (http is allowed for localhost)"
            return
        }

        isLoadingModels = true
        modelLoadStatus = "Loading models"

        Task {
            do {
                let models = try await AIEnrichmentClient().models(endpointURL: url, apiKey: apiKey)
                availableModels = models
                if enabledModelNames.isEmpty {
                    enabledModelNames = Set(models.map(\.name))
                } else {
                    enabledModelNames = enabledModelNames.intersection(Set(models.map(\.name)))
                    if enabledModelNames.isEmpty {
                        enabledModelNames = Set(models.map(\.name))
                    }
                }
                if !enabledModelNames.contains(model), let first = offeredModels.first {
                    model = first.name
                }
                modelLoadStatus = "Loaded \(models.count) models"
            } catch {
                modelLoadStatus = "Could not load models"
            }

            isLoadingModels = false
        }
    }

    func setModel(_ name: String, enabled: Bool) {
        if enabled {
            enabledModelNames.insert(name)
            if model.isEmpty {
                model = name
            }
        } else {
            enabledModelNames.remove(name)
            if model == name {
                model = offeredModels.first?.name ?? ""
            }
        }
    }

    private enum Keys {
        static let endpointURL = "ai.endpointURL"
        static let model = "ai.model"
        static let includeThumbnail = "ai.includeThumbnail"
        static let enabledModelNames = "ai.enabledModelNames"
        static let apiKeyStored = "ai.apiKeyStored"
        static let enrichmentEnabled = "ai.enrichmentEnabled"
        static let sourceLookupEnabled = "ai.sourceLookupEnabled"
    }

    private func persistAPIKey(_ value: String) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if defaults.bool(forKey: Keys.apiKeyStored) {
                try? keychain.save("")
            }
            defaults.set(false, forKey: Keys.apiKeyStored)
            return
        }

        do {
            try keychain.save(value)
            defaults.set(true, forKey: Keys.apiKeyStored)
        } catch {
            modelLoadStatus = "API key could not be stored"
        }
    }
}

private struct APIKeyKeychain {
    private let service = "com.printfilemanager.PrintFileManager"
    private let account = "ai.apiKey"

    func load() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unexpectedStatus(status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        if value.isEmpty {
            try delete()
            return
        }

        let data = Data(value.utf8)
        var query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.unexpectedStatus(updateStatus) }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    private func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }
}

private extension URL {
    /// Local model servers are commonly plain http, which is fine because the traffic never
    /// leaves the machine. Everything else must be https.
    var isLocalhost: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }
}
