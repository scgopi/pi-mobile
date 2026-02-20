import Foundation
import PiAgentCore
import PiAI

/// Protocol for Pi extensions that can add tools and intercept lifecycle events.
public protocol PiExtension: Sendable {
    /// Unique identifier for this extension.
    var id: String { get }

    /// Display name for this extension.
    var name: String { get }

    /// Description of what this extension does.
    var description: String { get }

    /// Additional tools provided by this extension.
    var tools: [any Tool] { get }

    /// Called when the extension is loaded.
    func onLoad() async

    /// Called when the extension is unloaded.
    func onUnload() async

    /// Called before a tool is executed. Return a decision on whether to proceed.
    func beforeToolCall(name: String, input: JSONValue) async -> ToolCallDecision

    /// Called after a tool has been executed.
    func afterToolCall(name: String, result: AgentToolResult) async

    /// Called before a message is sent to the LLM.
    func beforeLlmCall(context: Context) async -> Context

    /// Called after a response is received from the LLM.
    func afterLlmResponse(content: String) async
}

// MARK: - Default Implementations

public extension PiExtension {
    var tools: [any Tool] { [] }

    func onLoad() async {}
    func onUnload() async {}

    func beforeToolCall(name: String, input: JSONValue) async -> ToolCallDecision {
        return .allow
    }

    func afterToolCall(name: String, result: AgentToolResult) async {}

    func beforeLlmCall(context: Context) async -> Context {
        return context
    }

    func afterLlmResponse(content: String) async {}
}
