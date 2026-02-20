import Foundation

// MARK: - Wire Protocol

public enum WireProtocol: String, Codable, CaseIterable, Sendable {
    case openaiCompletions = "openai-completions"
    case openaiResponses = "openai-responses"
    case anthropic
    case google
    case azure = "azure"
}

// MARK: - Model

public struct ModelCapabilities: Codable, Sendable {
    public let vision: Bool
    public let toolUse: Bool
    public let streaming: Bool
    public let reasoning: Bool

    public init(vision: Bool = false, toolUse: Bool = false, streaming: Bool = true, reasoning: Bool = false) {
        self.vision = vision
        self.toolUse = toolUse
        self.streaming = streaming
        self.reasoning = reasoning
    }
}

public struct ModelDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let protocolType: WireProtocol
    public let baseUrl: String
    public let contextWindow: Int
    public let maxOutputTokens: Int
    public let inputCostPer1M: Double
    public let outputCostPer1M: Double
    public let capabilities: ModelCapabilities

    public init(
        id: String,
        name: String,
        provider: String,
        protocolType: WireProtocol,
        baseUrl: String,
        contextWindow: Int,
        maxOutputTokens: Int,
        inputCostPer1M: Double,
        outputCostPer1M: Double,
        capabilities: ModelCapabilities = ModelCapabilities()
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.protocolType = protocolType
        self.baseUrl = baseUrl
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.inputCostPer1M = inputCostPer1M
        self.outputCostPer1M = outputCostPer1M
        self.capabilities = capabilities
    }
}

// MARK: - Messages

public enum Role: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum ContentBlock: Codable, Sendable {
    case text(String)
    case image(base64: String, mimeType: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, base64, mimeType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let base64 = try container.decode(String.self, forKey: .base64)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(base64: base64, mimeType: mimeType)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let base64, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(base64, forKey: .base64)
            try container.encode(mimeType, forKey: .mimeType)
        }
    }
}

public enum MessageContent: Sendable {
    case text(String)
    case blocks([ContentBlock])

    public var textValue: String {
        switch self {
        case .text(let text):
            return text
        case .blocks(let blocks):
            return blocks.compactMap { block in
                if case .text(let text) = block { return text }
                return nil
            }.joined()
        }
    }
}

public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ToolCall: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public var arguments: String // Raw JSON string

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public var input: JSONValue {
        guard let data = arguments.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return .object([:])
        }
        return value
    }
}

public struct ToolResult: Sendable, Codable {
    public let toolCallId: String
    public let output: String
    public let isError: Bool

    public init(toolCallId: String, output: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.output = output
        self.isError = isError
    }
}

public struct Message: Sendable {
    public let role: Role
    public let content: MessageContent
    public var toolCalls: [ToolCall]?
    public var toolResults: [ToolResult]?
    public var thinking: String?

    public init(
        role: Role,
        content: MessageContent,
        toolCalls: [ToolCall]? = nil,
        toolResults: [ToolResult]? = nil,
        thinking: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.thinking = thinking
    }
}

// MARK: - Context

public struct Context: Sendable {
    public var systemPrompt: String
    public var messages: [Message]
    public var tools: [ToolDefinition]?
    public var temperature: Double?
    public var maxTokens: Int?

    public init(
        systemPrompt: String = "",
        messages: [Message] = [],
        tools: [ToolDefinition]? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

// MARK: - Stream Events

public enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCallEnd(id: String)
    case usage(inputTokens: Int, outputTokens: Int)
    case done
    case error(String)
}

// MARK: - Errors

public enum LlmError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)
    case parseError(String)
    case networkError(Error)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        }
    }
}
