import Foundation
import PiAgentCore
import PiAI

public struct ListFilesTool: Tool, Sendable {
    public let name = "list_files"
    public let description = "List files and directories. Supports optional glob patterns and recursive listing."

    private let sandboxURL: URL

    public init(sandboxURL: URL) {
        self.sandboxURL = sandboxURL
    }

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Directory path relative to sandbox. Defaults to root."),
                ]),
                "pattern": .object([
                    "type": .string("string"),
                    "description": .string("Glob pattern to filter results (e.g., '*.swift', '**/*.json')"),
                ]),
                "recursive": .object([
                    "type": .string("boolean"),
                    "description": .string("Whether to list recursively. Defaults to false."),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        let relativePath = input["path"]?.stringValue ?? ""
        let pattern = input["pattern"]?.stringValue
        let recursive = input["recursive"]?.boolValue ?? false

        let dirURL = relativePath.isEmpty ? sandboxURL : sandboxURL.appendingPathComponent(relativePath)

        guard dirURL.standardizedFileURL.path.hasPrefix(sandboxURL.standardizedFileURL.path) else {
            return AgentToolResult(output: "Error: Path is outside sandbox", isError: true)
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return AgentToolResult(output: "Error: Directory not found: \(relativePath)", isError: true)
        }

        var entries: [(String, Bool)] = [] // (path, isDirectory)

        if recursive {
            guard let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return AgentToolResult(output: "Error: Could not enumerate directory", isError: true)
            }

            while let itemURL = enumerator.nextObject() as? URL {
                let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let relativePath = itemURL.path.replacingOccurrences(of: sandboxURL.path + "/", with: "")
                entries.append((relativePath, isDirectory))
            }
        } else {
            let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let relativePath = itemURL.path.replacingOccurrences(of: sandboxURL.path + "/", with: "")
                entries.append((relativePath, isDirectory))
            }
        }

        // Apply glob pattern filter
        if let pattern = pattern {
            entries = entries.filter { matchesGlob(path: $0.0, pattern: pattern) }
        }

        if entries.isEmpty {
            return AgentToolResult(output: "No files found")
        }

        let output = entries.map { path, isDir in
            isDir ? "\(path)/" : path
        }.joined(separator: "\n")

        return AgentToolResult(
            output: "\(entries.count) entries:\n\(output)"
        )
    }

    /// Simple glob matching supporting * and ** patterns.
    private func matchesGlob(path: String, pattern: String) -> Bool {
        // Convert glob pattern to regex
        var regex = "^"
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let ch = pattern[i]
            if ch == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    // ** matches any path segment
                    regex += ".*"
                    i = pattern.index(after: next)
                    // Skip following /
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                } else {
                    // * matches anything except /
                    regex += "[^/]*"
                }
            } else if ch == "?" {
                regex += "[^/]"
            } else if ch == "." {
                regex += "\\."
            } else {
                regex += String(ch)
            }
            i = pattern.index(after: i)
        }
        regex += "$"

        return path.range(of: regex, options: .regularExpression) != nil
    }
}
