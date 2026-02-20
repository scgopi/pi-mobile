import Foundation
import os
import PiAI
import PiAgentCore
import PiTools
import PiSession
import PiExtensions

private let logger = Logger(subsystem: "com.pi.ai", category: "AgentRepository")

/// Connects ViewModels to the agent loop, session storage, and extensions.
@MainActor
public final class AgentRepository: ObservableObject {
    private let llmClient: LlmClient
    private let agentLoop: AgentLoop
    private let sessionRepository: SessionRepository
    private let extensionRegistry: ExtensionRegistry
    private let modelCatalogue: ModelCatalogue
    private let apiKeyRepository: ApiKeyRepository

    private var currentTask: Task<Void, Never>?

    public init(
        sessionDatabase: SessionDatabase,
        modelCatalogue: ModelCatalogue,
        apiKeyRepository: ApiKeyRepository
    ) {
        self.llmClient = LlmClient()
        self.agentLoop = AgentLoop(llmClient: llmClient)
        self.sessionRepository = SessionRepository(database: sessionDatabase)
        self.extensionRegistry = ExtensionRegistry()
        self.modelCatalogue = modelCatalogue
        self.apiKeyRepository = apiKeyRepository
    }

    // MARK: - Session Management

    public func createSession(title: String, provider: String, modelId: String, systemPrompt: String = "") throws -> Session {
        let session = Session(
            title: title,
            modelProvider: provider,
            modelId: modelId,
            systemPrompt: systemPrompt
        )
        try sessionRepository.createSession(session)
        return session
    }

    public func listSessions() throws -> [Session] {
        try sessionRepository.listSessions()
    }

    public func deleteSession(id: String) throws {
        try sessionRepository.deleteSession(id: id)
    }

    public func getBranch(leafId: String) throws -> [Entry] {
        try sessionRepository.getBranch(leafId: leafId)
    }

    public func getLatestLeaf(sessionId: String) throws -> Entry? {
        try sessionRepository.latestLeaf(sessionId: sessionId)
    }

    // MARK: - Agent Execution

    public func sendMessage(
        sessionId: String,
        parentEntryId: String?,
        text: String,
        model: ModelDefinition,
        systemPrompt: String,
        onLeafUpdated: @escaping (String) -> Void = { _ in },
        onEvent: @escaping (AgentEvent) -> Void
    ) {
        currentTask?.cancel()

        currentTask = Task {
            do {
                guard let apiKey = apiKeyRepository.get(provider: model.provider) else {
                    onEvent(.error("No API key configured for \(model.provider)"))
                    onEvent(.done)
                    return
                }

                // For Azure, override the model's baseUrl with the user-configured endpoint
                var resolvedModel = model
                if model.provider == "azure" || model.protocolType == .azure {
                    if let endpoint = apiKeyRepository.getSetting(provider: "azure", key: "endpoint"),
                       !endpoint.isEmpty {
                        resolvedModel = ModelDefinition(
                            id: model.id,
                            name: model.name,
                            provider: model.provider,
                            protocolType: model.protocolType,
                            baseUrl: endpoint,
                            contextWindow: model.contextWindow,
                            maxOutputTokens: model.maxOutputTokens,
                            inputCostPer1M: model.inputCostPer1M,
                            outputCostPer1M: model.outputCostPer1M,
                            capabilities: model.capabilities
                        )
                    }
                }

                // Save user entry (if parentEntryId is stale, fall back to nil)
                var userEntry = Entry(
                    sessionId: sessionId,
                    parentId: parentEntryId,
                    role: "user",
                    content: text
                )
                do {
                    try sessionRepository.addEntry(userEntry)
                } catch {
                    // FK constraint failure — parentId references a deleted entry; retry with nil
                    userEntry = Entry(
                        id: userEntry.id,
                        sessionId: sessionId,
                        parentId: nil,
                        role: "user",
                        content: text
                    )
                    try sessionRepository.addEntry(userEntry)
                }

                // Build context from branch
                let branch = try sessionRepository.getBranch(leafId: userEntry.id)
                var messages: [Message] = branch.map { entry in
                    let role: Role = entry.role == "user" ? .user : .assistant
                    var toolCalls: [ToolCall]? = nil
                    var toolResults: [ToolResult]? = nil

                    if let toolCallsJson = entry.toolCalls,
                       let data = toolCallsJson.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([ToolCall].self, from: data) {
                        toolCalls = decoded
                    }

                    if let toolResultsJson = entry.toolResults,
                       let data = toolResultsJson.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([ToolResult].self, from: data) {
                        toolResults = decoded
                    }

                    return Message(
                        role: role,
                        content: .text(entry.content),
                        toolCalls: toolCalls,
                        toolResults: toolResults,
                        thinking: entry.thinking
                    )
                }

                // Build tools
                let sandboxURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                var tools: [any Tool] = BuiltInTools.create(sandboxURL: sandboxURL)
                tools.append(contentsOf: extensionRegistry.allTools())

                var context = Context(
                    systemPrompt: systemPrompt,
                    messages: messages,
                    temperature: 0.7,
                    maxTokens: resolvedModel.maxOutputTokens
                )

                // Run agent loop
                let stream = agentLoop.run(
                    model: resolvedModel,
                    context: &context,
                    tools: tools,
                    apiKey: apiKey
                )

                var fullContent = ""
                var fullThinking: String? = nil
                var inputTokens = 0
                var outputTokens = 0

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case .streamDelta(let delta):
                        fullContent += delta
                    case .thinkingDelta(let delta):
                        fullThinking = (fullThinking ?? "") + delta
                    case .usageUpdate(let input, let output):
                        inputTokens += input
                        outputTokens += output
                    default:
                        break
                    }

                    onEvent(event)
                }

                // Save assistant entry
                if !fullContent.isEmpty {
                    let assistantEntry = Entry(
                        sessionId: sessionId,
                        parentId: userEntry.id,
                        role: "assistant",
                        content: fullContent,
                        thinking: fullThinking,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens
                    )
                    try sessionRepository.addEntry(assistantEntry)
                    onLeafUpdated(assistantEntry.id)
                } else {
                    onLeafUpdated(userEntry.id)
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("[AgentRepo] Error: \(error.localizedDescription)")
                    onEvent(.error(error.localizedDescription))
                    onEvent(.done)
                }
            }
        }
    }

    public func cancelStreaming() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Catalogue

    public func getModelCatalogue() -> ModelCatalogue {
        return modelCatalogue
    }

    public func getSessionRepository() -> SessionRepository {
        return sessionRepository
    }
}
