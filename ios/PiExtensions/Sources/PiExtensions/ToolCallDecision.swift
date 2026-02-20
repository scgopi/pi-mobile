import Foundation
import PiAI

/// Decision for whether a tool call should proceed.
public enum ToolCallDecision: Sendable {
    /// Allow the tool call to proceed as-is.
    case allow

    /// Block the tool call with a reason.
    case block(reason: String)

    /// Allow the tool call but modify the input.
    case modify(input: JSONValue)
}
