import Foundation
import PiAgentCore

public struct BuiltInTools {
    /// Create all built-in tools with the given sandbox URL.
    public static func create(sandboxURL: URL) -> [any Tool] {
        [
            ReadFileTool(sandboxURL: sandboxURL),
            WriteFileTool(sandboxURL: sandboxURL),
            EditFileTool(sandboxURL: sandboxURL),
            ListFilesTool(sandboxURL: sandboxURL),
            SqliteQueryTool(),
            HttpRequestTool(),
            MediaQueryTool(),
            ExternalFileTool(),
        ]
    }
}
