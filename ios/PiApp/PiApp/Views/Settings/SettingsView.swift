import SwiftUI
import PiAI

struct SettingsView: View {
    let apiKeyRepository: ApiKeyRepository
    let modelCatalogue: ModelCatalogue
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeys: [String: String] = [:]
    @State private var editingProvider: String?
    @State private var editingKey: String = ""
    @State private var showSaveConfirmation = false
    @State private var azureEndpoint: String = ""
    @State private var azureEndpointSaved = false

    private let knownProviders = ["anthropic", "openai", "azure", "google", "openrouter", "cerebras", "mistral"]

    var body: some View {
        NavigationStack {
            Form {
                Section("API Keys") {
                    ForEach(knownProviders, id: \.self) { provider in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(provider.capitalized)
                                    .font(.body)
                                if apiKeyRepository.hasKey(provider: provider) {
                                    Text("Configured")
                                        .font(.caption)
                                        .foregroundStyle(Theme.success)
                                } else {
                                    Text("Not set")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }

                            Spacer()

                            Button(apiKeyRepository.hasKey(provider: provider) ? "Edit" : "Add") {
                                editingProvider = provider
                                editingKey = apiKeyRepository.get(provider: provider) ?? ""
                            }
                            .font(.callout)
                        }
                    }
                }

                Section(header: Text("Azure Endpoint"), footer: Text("Full Azure OpenAI resource URL, e.g.\nhttps://myresource.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview")) {
                    TextField("Azure Endpoint URL", text: $azureEndpoint)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Button("Save") {
                            try? apiKeyRepository.saveSetting(provider: "azure", key: "endpoint", value: azureEndpoint)
                            azureEndpointSaved = true
                        }
                        .disabled(azureEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if azureEndpointSaved {
                            Text("Saved")
                                .font(.caption)
                                .foregroundStyle(Theme.success)
                        }
                    }
                }
                .onAppear {
                    azureEndpoint = apiKeyRepository.getSetting(provider: "azure", key: "endpoint") ?? ""
                    azureEndpointSaved = !azureEndpoint.isEmpty
                }

                Section("Models") {
                    let providers = modelCatalogue.allProviders()
                    if providers.isEmpty {
                        Text("No models loaded. Add the model-catalogue.json to the app bundle.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(providers, id: \.self) { provider in
                            let models = modelCatalogue.models(for: provider)
                            DisclosureGroup("\(provider.capitalized) (\(models.count) models)") {
                                ForEach(models) { model in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.name)
                                            .font(.callout)
                                        HStack {
                                            Text("Context: \(model.contextWindow / 1000)K")
                                            Text("Protocol: \(model.protocolType.rawValue)")
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingProvider) { provider in
                ApiKeyEditor(
                    provider: provider,
                    apiKey: apiKeyRepository.get(provider: provider) ?? "",
                    onSave: { key in
                        try? apiKeyRepository.save(provider: provider, apiKey: key)
                        editingProvider = nil
                    },
                    onDelete: {
                        try? apiKeyRepository.delete(provider: provider)
                        editingProvider = nil
                    }
                )
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct ApiKeyEditor: View {
    let provider: String
    @State var apiKey: String
    let onSave: (String) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("\(provider.capitalized) API Key") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if !apiKey.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Remove API Key")
                        }
                    }
                }
            }
            .navigationTitle("Edit API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(apiKey)
                        dismiss()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
