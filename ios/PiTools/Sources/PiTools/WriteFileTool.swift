import Foundation
import PiAgentCore
import PiAI

public struct WriteFileTool: Tool, Sendable {
    public let name = "write_file"
    public let description = "Write content to a file. Creates parent directories if needed. Restricted to the sandbox directory."

    private let sandboxURL: URL

    public init(sandboxURL: URL) {
        self.sandboxURL = sandboxURL
    }

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("path"), .string("content")]),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Path to the file to write, relative to sandbox"),
                ]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("Content to write to the file"),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        guard let path = input["path"]?.stringValue else {
            return AgentToolResult(output: "Error: 'path' parameter is required", isError: true)
        }
        guard let content = input["content"]?.stringValue else {
            return AgentToolResult(output: "Error: 'content' parameter is required", isError: true)
        }

        let fileURL = sandboxURL.appendingPathComponent(path)

        // Validate path is within sandbox
        guard fileURL.standardizedFileURL.path.hasPrefix(sandboxURL.standardizedFileURL.path) else {
            return AgentToolResult(output: "Error: Path is outside sandbox", isError: true)
        }

        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()

        // Create parent directories
        if !fm.fileExists(atPath: directory.path) {
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return AgentToolResult(output: "Error creating directory: \(error.localizedDescription)", isError: true)
            }
        }

        // Write file
        guard let data = content.data(using: .utf8) else {
            return AgentToolResult(output: "Error: Could not encode content as UTF-8", isError: true)
        }

        do {
            try data.write(to: fileURL)
        } catch {
            return AgentToolResult(output: "Error writing file: \(error.localizedDescription)", isError: true)
        }

        let lineCount = content.components(separatedBy: "\n").count
        return AgentToolResult(
            output: "Wrote \(data.count) bytes (\(lineCount) lines) to \(path)",
            details: .file(path: path, content: content, language: nil)
        )
    }
}
