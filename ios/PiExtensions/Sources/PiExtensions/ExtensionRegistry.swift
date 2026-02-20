import Foundation
import PiAgentCore
import PiAI

/// Manages loaded extensions, aggregates tools, and dispatches lifecycle hooks.
public final class ExtensionRegistry: @unchecked Sendable {
    private var extensions: [String: any PiExtension] = [:]
    private let lock = NSLock()

    public init() {}

    /// Register an extension.
    public func register(_ ext: any PiExtension) async {
        lock.withLock { extensions[ext.id] = ext }
        await ext.onLoad()
    }

    /// Unregister an extension by ID.
    public func unregister(id: String) async {
        let ext = lock.withLock { extensions.removeValue(forKey: id) }
        if let ext = ext {
            await ext.onUnload()
        }
    }

    /// Get an extension by ID.
    public func get(id: String) -> (any PiExtension)? {
        lock.lock()
        defer { lock.unlock() }
        return extensions[id]
    }

    /// Get all registered extensions.
    public func allExtensions() -> [any PiExtension] {
        lock.lock()
        defer { lock.unlock() }
        return Array(extensions.values)
    }

    /// Aggregate all tools from all registered extensions.
    public func allTools() -> [any Tool] {
        lock.lock()
        let exts = Array(extensions.values)
        lock.unlock()
        return exts.flatMap { $0.tools }
    }

    /// Dispatch beforeToolCall to all extensions. Returns the first non-allow decision, or .allow if all pass.
    public func dispatchBeforeToolCall(name: String, input: JSONValue) async -> ToolCallDecision {
        let exts = allExtensions()
        for ext in exts {
            let decision = await ext.beforeToolCall(name: name, input: input)
            switch decision {
            case .allow:
                continue
            case .block, .modify:
                return decision
            }
        }
        return .allow
    }

    /// Dispatch afterToolCall to all extensions.
    public func dispatchAfterToolCall(name: String, result: AgentToolResult) async {
        let exts = allExtensions()
        for ext in exts {
            await ext.afterToolCall(name: name, result: result)
        }
    }

    /// Dispatch beforeLlmCall, chaining context modifications.
    public func dispatchBeforeLlmCall(context: Context) async -> Context {
        let exts = allExtensions()
        var ctx = context
        for ext in exts {
            ctx = await ext.beforeLlmCall(context: ctx)
        }
        return ctx
    }

    /// Dispatch afterLlmResponse to all extensions.
    public func dispatchAfterLlmResponse(content: String) async {
        let exts = allExtensions()
        for ext in exts {
            await ext.afterLlmResponse(content: content)
        }
    }
}
