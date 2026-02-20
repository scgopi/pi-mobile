import Foundation
import PiAI

// MARK: - Tool Protocol

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parametersSchema: JSONValue { get }
    func execute(input: JSONValue) async throws -> AgentToolResult
}

// MARK: - Tool Result

public struct AgentToolResult: Sendable {
    public let toolCallId: String
    public let output: String
    public let details: ToolResultDetails?
    public let isError: Bool

    public init(toolCallId: String = "", output: String, details: ToolResultDetails? = nil, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.output = output
        self.details = details
        self.isError = isError
    }
}

// MARK: - Tool Result Details

public enum ToolResultDetails: Sendable {
    case file(path: String, content: String, language: String?)
    case diff(path: String, hunks: [DiffHunk])
    case table(columns: [String], rows: [[String]])
    case error(message: String, code: String?)
}

// MARK: - Diff Types

public struct DiffHunk: Sendable {
    public let startLineOld: Int
    public let countOld: Int
    public let startLineNew: Int
    public let countNew: Int
    public let lines: [DiffLine]

    public init(startLineOld: Int, countOld: Int, startLineNew: Int, countNew: Int, lines: [DiffLine]) {
        self.startLineOld = startLineOld
        self.countOld = countOld
        self.startLineNew = startLineNew
        self.countNew = countNew
        self.lines = lines
    }
}

public struct DiffLine: Sendable {
    public let type: DiffLineType
    public let content: String

    public init(type: DiffLineType, content: String) {
        self.type = type
        self.content = content
    }
}

public enum DiffLineType: Sendable {
    case context
    case add
    case remove
}

// MARK: - Agent Events

public enum AgentEvent: Sendable {
    case streamDelta(String)
    case thinkingDelta(String)
    case assistantMessage(content: String, thinking: String?)
    case toolCallStarted(name: String, input: JSONValue)
    case toolCallCompleted(name: String, result: AgentToolResult)
    case usageUpdate(inputTokens: Int, outputTokens: Int)
    case error(String)
    case done
}
