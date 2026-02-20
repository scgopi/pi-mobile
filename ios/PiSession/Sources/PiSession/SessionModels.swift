import Foundation
import GRDB
import PiAI

// MARK: - Session

public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var modelProvider: String
    public var modelId: String
    public var systemPrompt: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        modelProvider: String,
        modelId: String,
        systemPrompt: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.modelProvider = modelProvider
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Session: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "sessions"

    enum Columns: String, ColumnExpression {
        case id
        case title
        case modelProvider = "model_provider"
        case modelId = "model_id"
        case systemPrompt = "system_prompt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case title
        case modelProvider = "model_provider"
        case modelId = "model_id"
        case systemPrompt = "system_prompt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Entry

public struct Entry: Codable, Identifiable, Sendable {
    public var id: String
    public var sessionId: String
    public var parentId: String?
    public var role: String
    public var content: String
    public var toolCalls: String?
    public var toolResults: String?
    public var thinking: String?
    public var inputTokens: Int
    public var outputTokens: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        parentId: String? = nil,
        role: String,
        content: String,
        toolCalls: String? = nil,
        toolResults: String? = nil,
        thinking: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.parentId = parentId
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.thinking = thinking
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.createdAt = createdAt
    }
}

extension Entry: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "entries"

    enum Columns: String, ColumnExpression {
        case id
        case sessionId = "session_id"
        case parentId = "parent_id"
        case role
        case content
        case toolCalls = "tool_calls"
        case toolResults = "tool_results"
        case thinking
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case createdAt = "created_at"
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case parentId = "parent_id"
        case role
        case content
        case toolCalls = "tool_calls"
        case toolResults = "tool_results"
        case thinking
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case createdAt = "created_at"
    }
}

// MARK: - Branch Info

public struct BranchInfo: Sendable {
    public let leafId: String
    public let entryCount: Int
    public let lastContent: String
    public let lastUpdated: Date

    public init(leafId: String, entryCount: Int, lastContent: String, lastUpdated: Date) {
        self.leafId = leafId
        self.entryCount = entryCount
        self.lastContent = lastContent
        self.lastUpdated = lastUpdated
    }
}
