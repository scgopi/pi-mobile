import Foundation
import os
import SwiftUI
import PiAI
import PiAgentCore
import PiSession

private let logger = Logger(subsystem: "com.pi.ai", category: "ChatViewModel")

/// Represents a displayable message in the chat.
public struct ChatMessage: Identifiable {
    public let id: String
    public let role: String
    public let content: String
    public var thinking: String?
    public var toolCalls: [DisplayToolCall]
    public var isStreaming: Bool

    public init(id: String = UUID().uuidString, role: String, content: String, thinking: String? = nil, toolCalls: [DisplayToolCall] = [], isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.isStreaming = isStreaming
    }
}

public struct DisplayToolCall: Identifiable {
    public let id: String
    public let name: String
    public var input: String
    public var output: String?
    public var isError: Bool
    public var details: ToolResultDetails?
    public var isComplete: Bool

    public init(id: String = UUID().uuidString, name: String, input: String = "", output: String? = nil, isError: Bool = false, details: ToolResultDetails? = nil, isComplete: Bool = false) {
        self.id = id
        self.name = name
        self.input = input
        self.output = output
        self.isError = isError
        self.details = details
        self.isComplete = isComplete
    }
}

@MainActor
@Observable
public final class ChatViewModel {
    public var messages: [ChatMessage] = []
    public var isStreaming = false
    public var streamingText = ""
    public var streamingThinking = ""
    public var activeToolCall: DisplayToolCall?
    public var currentModel: ModelDefinition?
    public var error: String?
    public var inputText = ""

    public var sessionId: String?
    public var session: Session?
    private var currentLeafId: String?

    private let agentRepository: AgentRepository

    public init(agentRepository: AgentRepository) {
        self.agentRepository = agentRepository
    }

    public func loadSession(_ session: Session) {
        self.session = session
        self.sessionId = session.id
        self.messages = []
        self.currentLeafId = nil

        // Load existing messages from the latest branch
        do {
            if let leaf = try agentRepository.getLatestLeaf(sessionId: session.id) {
                currentLeafId = leaf.id
                let entries = try agentRepository.getBranch(leafId: leaf.id)
                messages = entries.map { entry in
                    ChatMessage(
                        id: entry.id,
                        role: entry.role,
                        content: entry.content,
                        thinking: entry.thinking
                    )
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        // Set model from session
        let catalogue = agentRepository.getModelCatalogue()
        currentModel = catalogue.get(provider: session.modelProvider, id: session.modelId)
    }

    public func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard let model = currentModel, let sessionId = sessionId else {
            error = "No model or session selected"
            return
        }

        inputText = ""
        error = nil

        // Add user message
        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)

        // Start streaming
        isStreaming = true
        streamingText = ""
        streamingThinking = ""

        // Add placeholder for assistant response
        let assistantMessageId = UUID().uuidString
        messages.append(ChatMessage(id: assistantMessageId, role: "assistant", content: "", isStreaming: true))

        agentRepository.sendMessage(
            sessionId: sessionId,
            parentEntryId: currentLeafId,
            text: text,
            model: model,
            systemPrompt: session?.systemPrompt ?? "",
            onLeafUpdated: { [weak self] leafId in
                Task { @MainActor in
                    self?.currentLeafId = leafId
                }
            }
        ) { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleAgentEvent(event, assistantMessageId: assistantMessageId)
            }
        }
    }

    private func handleAgentEvent(_ event: AgentEvent, assistantMessageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == assistantMessageId }) else { return }

        switch event {
        case .streamDelta(let delta):
            streamingText += delta
            messages[index] = ChatMessage(
                id: assistantMessageId,
                role: "assistant",
                content: streamingText,
                thinking: streamingThinking.isEmpty ? nil : streamingThinking,
                toolCalls: messages[index].toolCalls,
                isStreaming: true
            )

        case .thinkingDelta(let delta):
            streamingThinking += delta
            messages[index] = ChatMessage(
                id: assistantMessageId,
                role: "assistant",
                content: streamingText,
                thinking: streamingThinking,
                toolCalls: messages[index].toolCalls,
                isStreaming: true
            )

        case .toolCallStarted(let name, _):
            let toolCall = DisplayToolCall(name: name)
            activeToolCall = toolCall
            var updatedMsg = messages[index]
            updatedMsg.toolCalls.append(toolCall)
            messages[index] = updatedMsg

        case .toolCallCompleted(let name, let result):
            if let toolIndex = messages[index].toolCalls.lastIndex(where: { $0.name == name }) {
                messages[index].toolCalls[toolIndex].output = result.output
                messages[index].toolCalls[toolIndex].isError = result.isError
                messages[index].toolCalls[toolIndex].details = result.details
                messages[index].toolCalls[toolIndex].isComplete = true
            }
            activeToolCall = nil

        case .assistantMessage(let content, let thinking):
            streamingText = content
            if let thinking = thinking { streamingThinking = thinking }

        case .usageUpdate:
            break

        case .error(let message):
            error = message

        case .done:
            isStreaming = false
            messages[index] = ChatMessage(
                id: assistantMessageId,
                role: "assistant",
                content: streamingText,
                thinking: streamingThinking.isEmpty ? nil : streamingThinking,
                toolCalls: messages[index].toolCalls,
                isStreaming: false
            )
            streamingText = ""
            streamingThinking = ""
        }
    }

    public func cancelStreaming() {
        agentRepository.cancelStreaming()
        isStreaming = false
    }
}
