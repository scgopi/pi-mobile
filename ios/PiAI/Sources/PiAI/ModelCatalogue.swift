import Foundation

public final class ModelCatalogue: @unchecked Sendable {
    private var models: [String: ModelDefinition] = [:]
    private let lock = NSLock()

    public init() {}

    /// Load model catalogue from the app bundle's model-catalogue.json
    public func loadFromBundle(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "model-catalogue", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return }
        loadFromJSON(data)
    }

    /// Load model definitions from JSON data.
    /// Supports the nested catalogue format:
    /// ```
    /// { "providers": { "<provider>": { "displayName": "...", "defaultBaseUrl": "...", "protocol": "...", "models": { "<modelId>": { ... } } } } }
    /// ```
    public func loadFromJSON(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any]
        else { return }

        lock.lock()
        defer { lock.unlock() }

        for (providerKey, providerValue) in providers {
            guard let providerDict = providerValue as? [String: Any],
                  let defaultBaseUrl = providerDict["defaultBaseUrl"] as? String,
                  let protocolStr = providerDict["protocol"] as? String,
                  let protocolType = WireProtocol(rawValue: protocolStr),
                  let modelsDict = providerDict["models"] as? [String: Any]
            else { continue }

            for (modelId, modelValue) in modelsDict {
                guard let modelDict = modelValue as? [String: Any],
                      let name = modelDict["name"] as? String,
                      let contextWindow = modelDict["contextWindow"] as? Int,
                      let maxOutputTokens = modelDict["maxOutputTokens"] as? Int
                else { continue }

                let inputCost = modelDict["inputCostPer1M"] as? Double ?? 0
                let outputCost = modelDict["outputCostPer1M"] as? Double ?? 0
                let capsDict = modelDict["capabilities"] as? [String: Bool] ?? [:]

                let capabilities = ModelCapabilities(
                    vision: capsDict["vision"] ?? false,
                    toolUse: capsDict["toolUse"] ?? false,
                    streaming: capsDict["streaming"] ?? true,
                    reasoning: capsDict["reasoning"] ?? false
                )

                // Use model-level baseUrl if present, otherwise provider default
                let baseUrl = modelDict["baseUrl"] as? String ?? defaultBaseUrl

                let definition = ModelDefinition(
                    id: modelId,
                    name: name,
                    provider: providerKey,
                    protocolType: protocolType,
                    baseUrl: baseUrl,
                    contextWindow: contextWindow,
                    maxOutputTokens: maxOutputTokens,
                    inputCostPer1M: inputCost,
                    outputCostPer1M: outputCost,
                    capabilities: capabilities
                )

                models["\(providerKey)/\(modelId)"] = definition
            }
        }
    }

    /// Get a model definition by provider and id.
    public func get(provider: String, id: String) -> ModelDefinition? {
        lock.lock()
        defer { lock.unlock() }
        return models["\(provider)/\(id)"]
    }

    /// Get all models for a provider.
    public func models(for provider: String) -> [ModelDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return models.values.filter { $0.provider == provider }.sorted { $0.name < $1.name }
    }

    /// Get all models.
    public func allModels() -> [ModelDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return Array(models.values).sorted { $0.name < $1.name }
    }

    /// Get all provider names.
    public func allProviders() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(Set(models.values.map { $0.provider })).sorted()
    }
}
