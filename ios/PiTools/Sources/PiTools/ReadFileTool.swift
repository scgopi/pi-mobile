import Foundation
import PiAgentCore
import PiAI

public struct ReadFileTool: Tool, Sendable {
    public let name = "read_file"
    public let description = "Read the contents of a file. For text files, returns the content with line numbers. For images, returns base64-encoded data. Supports optional line range."

    private let sandboxURL: URL

    public init(sandboxURL: URL) {
        self.sandboxURL = sandboxURL
    }

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("path")]),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Path to the file to read, relative to sandbox"),
                ]),
                "start_line": .object([
                    "type": .string("integer"),
                    "description": .string("Starting line number (1-indexed). Optional."),
                ]),
                "end_line": .object([
                    "type": .string("integer"),
                    "description": .string("Ending line number (inclusive). Optional."),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        guard let path = input["path"]?.stringValue else {
            return AgentToolResult(output: "Error: 'path' parameter is required", isError: true)
        }

        let fileURL = sandboxURL.appendingPathComponent(path)

        // Validate path is within sandbox
        guard fileURL.standardizedFileURL.path.hasPrefix(sandboxURL.standardizedFileURL.path) else {
            return AgentToolResult(output: "Error: Path is outside sandbox", isError: true)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return AgentToolResult(output: "Error: File not found: \(path)", isError: true)
        }

        // Check if it's an image
        let ext = fileURL.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
        if imageExtensions.contains(ext) {
            guard let data = fm.contents(atPath: fileURL.path) else {
                return AgentToolResult(output: "Error: Could not read file", isError: true)
            }
            let base64 = data.base64EncodedString()
            let mimeType = mimeTypeForExtension(ext)
            return AgentToolResult(
                output: "Image file: \(path) (\(data.count) bytes, \(mimeType))\nBase64: \(base64.prefix(100))...",
                details: .file(path: path, content: "[base64:\(base64)]", language: nil)
            )
        }

        // Read text file
        guard let data = fm.contents(atPath: fileURL.path),
              let content = String(data: data, encoding: .utf8)
        else {
            return AgentToolResult(output: "Error: Could not read file as text", isError: true)
        }

        let allLines = content.components(separatedBy: "\n")
        let startLine = max(1, input["start_line"]?.intValue ?? 1)
        let endLine = min(allLines.count, input["end_line"]?.intValue ?? allLines.count)

        guard startLine <= endLine else {
            return AgentToolResult(output: "Error: Invalid line range \(startLine)-\(endLine)", isError: true)
        }

        let selectedLines = allLines[(startLine - 1)..<endLine]
        var output = ""
        for (index, line) in selectedLines.enumerated() {
            let lineNum = startLine + index
            output += "\(lineNum)\t\(line)\n"
        }

        let language = languageForExtension(ext)
        let info = "File: \(path) | Lines: \(startLine)-\(endLine) of \(allLines.count) | Language: \(language ?? "unknown")"

        return AgentToolResult(
            output: "\(info)\n\(output)",
            details: .file(path: path, content: output, language: language)
        )
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tiff": return "image/tiff"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
    }

    private func languageForExtension(_ ext: String) -> String? {
        switch ext {
        case "swift": return "swift"
        case "kt", "kts": return "kotlin"
        case "java": return "java"
        case "py": return "python"
        case "js": return "javascript"
        case "ts": return "typescript"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "c", "h": return "c"
        case "cpp", "hpp", "cc": return "cpp"
        case "cs": return "csharp"
        case "json": return "json"
        case "xml": return "xml"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "md", "markdown": return "markdown"
        case "html", "htm": return "html"
        case "css": return "css"
        case "sh", "bash", "zsh": return "shell"
        case "sql": return "sql"
        case "txt": return "plaintext"
        default: return nil
        }
    }
}
