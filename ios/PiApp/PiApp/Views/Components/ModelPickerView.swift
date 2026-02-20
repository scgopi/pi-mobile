import SwiftUI
import PiAI

struct ModelPickerView: View {
    let modelCatalogue: ModelCatalogue
    @Binding var selectedProvider: String
    @Binding var selectedModelId: String
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    var filteredProviders: [String] {
        let providers = modelCatalogue.allProviders()
        if searchText.isEmpty { return providers }
        return providers.filter { provider in
            provider.localizedCaseInsensitiveContains(searchText)
            || modelCatalogue.models(for: provider).contains { model in
                model.name.localizedCaseInsensitiveContains(searchText)
                || model.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredProviders, id: \.self) { provider in
                    let models = filteredModels(for: provider)
                    if !models.isEmpty {
                        Section(provider.capitalized) {
                            ForEach(models) { model in
                                ModelRow(
                                    model: model,
                                    isSelected: model.provider == selectedProvider && model.id == selectedModelId
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProvider = model.provider
                                    selectedModelId = model.id
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search models")
            .navigationTitle("Select Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func filteredModels(for provider: String) -> [ModelDefinition] {
        let models = modelCatalogue.models(for: provider)
        if searchText.isEmpty { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct ModelRow: View {
    let model: ModelDefinition
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: Theme.paddingMedium) {
                    Label("\(model.contextWindow / 1000)K", systemImage: "text.alignleft")
                    if model.capabilities.vision {
                        Label("Vision", systemImage: "eye")
                    }
                    if model.capabilities.toolUse {
                        Label("Tools", systemImage: "wrench")
                    }
                    if model.capabilities.reasoning {
                        Label("Reasoning", systemImage: "brain")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.primaryVariant)
            }
        }
        .padding(.vertical, 2)
    }
}
