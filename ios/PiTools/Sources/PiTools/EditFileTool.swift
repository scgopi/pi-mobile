import Foundation
import PiAgentCore
import PiAI

public struct EditFileTool: Tool, Sendable {
    public let name = "edit_file"
    public let description = "Edit a file by performing exact search and replace. The old_string must match exactly one location in the file."

    private let sandboxURL: URL

    public init(sandboxURL: URL) {
        self.sandboxURL = sandboxURL
    }

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("path"), .string("old_string"), .string("new_string")]),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Path to the file to edit, relative to sandbox"),
                ]),
                "old_string": .object([
                    "type": .string("string"),
                    "description": .string("The exact string to search for"),
                ]),
                "new_string": .object([
                    "type": .string("string"),
                    "description": .string("The replacement string"),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        guard let path = input["path"]?.stringValue else {
            return AgentToolResult(output: "Error: 'path' parameter is required", isError: true)
        }
        guard let oldString = input["old_string"]?.stringValue else {
            return AgentToolResult(output: "Error: 'old_string' parameter is required", isError: true)
        }
        guard let newString = input["new_string"]?.stringValue else {
            return AgentToolResult(output: "Error: 'new_string' parameter is required", isError: true)
        }

        let fileURL = sandboxURL.appendingPathComponent(path)

        guard fileURL.standardizedFileURL.path.hasPrefix(sandboxURL.standardizedFileURL.path) else {
            return AgentToolResult(output: "Error: Path is outside sandbox", isError: true)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return AgentToolResult(output: "Error: File not found: \(path)", isError: true)
        }

        guard let data = fm.contents(atPath: fileURL.path),
              let content = String(data: data, encoding: .utf8)
        else {
            return AgentToolResult(output: "Error: Could not read file as text", isError: true)
        }

        // Count occurrences
        let occurrences = content.components(separatedBy: oldString).count - 1
        if occurrences == 0 {
            return AgentToolResult(output: "Error: old_string not found in file", isError: true)
        }
        if occurrences > 1 {
            return AgentToolResult(output: "Error: old_string found \(occurrences) times. Must match exactly once.", isError: true)
        }

        // Perform replacement
        let newContent = content.replacingOccurrences(of: oldString, with: newString)

        guard let newData = newContent.data(using: .utf8) else {
            return AgentToolResult(output: "Error: Could not encode result as UTF-8", isError: true)
        }

        do {
            try newData.write(to: fileURL)
        } catch {
            return AgentToolResult(output: "Error writing file: \(error.localizedDescription)", isError: true)
        }

        // Generate diff info
        let hunks = generateDiff(old: oldString, new: newString, in: content)

        return AgentToolResult(
            output: "Edited \(path): replaced 1 occurrence",
            details: .diff(path: path, hunks: hunks)
        )
    }

    private func generateDiff(old: String, new: String, in content: String) -> [DiffHunk] {
        let contentLines = content.components(separatedBy: "\n")
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        // Find the start line of the match
        let contentJoined = content
        guard let matchRange = contentJoined.range(of: old) else { return [] }
        let startLine = contentJoined[contentJoined.startIndex..<matchRange.lowerBound].components(separatedBy: "\n").count

        var diffLines: [DiffLine] = []
        for line in oldLines {
            diffLines.append(DiffLine(type: .remove, content: line))
        }
        for line in newLines {
            diffLines.append(DiffLine(type: .add, content: line))
        }

        return [DiffHunk(
            startLineOld: startLine,
            countOld: oldLines.count,
            startLineNew: startLine,
            countNew: newLines.count,
            lines: diffLines
        )]
    }
}
