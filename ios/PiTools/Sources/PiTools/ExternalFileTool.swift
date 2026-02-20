import Foundation
import PiAgentCore
import PiAI

#if canImport(UIKit)
import UniformTypeIdentifiers
#endif

public struct ExternalFileTool: Tool, Sendable {
    public let name = "file_access"
    public let description = """
        Access files outside the app sandbox via the system file picker \
        (iCloud Drive, local storage, Dropbox, Google Drive, etc.). Actions:
        - "pick": Show file picker UI for user to select files or directories. Returns bookmark_id values for subsequent access. \
        Use content_types to filter (e.g. ["image"], ["pdf"], ["folder"]).
        - "export": Show save dialog to export text content as a new file at a user-chosen location.
        - "read": Read file contents using bookmark_id (and optional path for files within a picked directory). \
        Text files return numbered lines; images/binary return base64.
        - "write": Write text content to a file using bookmark_id (and optional path).
        - "list": List directory contents using a bookmark_id. Returns file names you can use as path in read/write/info.
        - "info": Get detailed metadata using bookmark_id (and optional path). Returns size, dates, type, iCloud status.
        - "grants": List all saved bookmark_id grants with validity status.
        - "revoke": Remove a saved bookmark_id grant.
        Typical flow: "pick" a directory to get bookmark_id, "list" it to see files, then "read" with bookmark_id + path. \
        Or "pick" individual files and "read" them directly by bookmark_id.
        """

    public init() {}

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("action")]),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "description": .string("Action to perform. Required."),
                    "enum": .array([
                        .string("pick"), .string("export"), .string("read"), .string("write"),
                        .string("list"), .string("info"), .string("grants"), .string("revoke"),
                    ]),
                ]),
                "content_types": .object([
                    "type": .string("array"),
                    "description": .string("(pick) File types to allow. Friendly names: 'image', 'pdf', 'text', 'video', 'audio', 'folder', 'any', 'json', 'csv', 'archive', 'source_code'. Also accepts UTType identifiers (e.g. 'public.jpeg') or file extensions (e.g. 'swift'). Defaults to ['any']."),
                    "items": .object(["type": .string("string")]),
                ]),
                "multiple": .object([
                    "type": .string("boolean"),
                    "description": .string("(pick) Allow selecting multiple files. Defaults to false."),
                ]),
                "bookmark_id": .object([
                    "type": .string("string"),
                    "description": .string("(read, write, list, info, revoke) Bookmark ID obtained from a previous 'pick' result."),
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("(read, write, info) Relative path within a bookmarked directory. Use file names from 'list' results. Not needed when bookmark_id points to a file directly."),
                ]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("(write, export) Text content to write or export as a file."),
                ]),
                "filename": .object([
                    "type": .string("string"),
                    "description": .string("(export) Suggested filename for the exported file. Defaults to 'export.txt'."),
                ]),
                "start_line": .object([
                    "type": .string("integer"),
                    "description": .string("(read) Starting line number (1-indexed) for text files. Optional."),
                ]),
                "end_line": .object([
                    "type": .string("integer"),
                    "description": .string("(read) Ending line number (inclusive) for text files. Optional."),
                ]),
                "recursive": .object([
                    "type": .string("boolean"),
                    "description": .string("(list) List directory recursively. Defaults to false."),
                ]),
                "pattern": .object([
                    "type": .string("string"),
                    "description": .string("(list) Glob pattern to filter results (e.g. '*.swift', '**/*.json')."),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        #if canImport(UIKit)
        let action = input["action"]?.stringValue ?? ""

        switch action {
        case "pick": return await handlePick(input: input)
        case "export": return await handleExport(input: input)
        case "read": return await handleRead(input: input)
        case "write": return await handleWrite(input: input)
        case "list": return await handleList(input: input)
        case "info": return await handleInfo(input: input)
        case "grants": return await handleGrants()
        case "revoke": return await handleRevoke(input: input)
        default:
            return AgentToolResult(
                output: "Error: Unknown action '\(action)'. Use: pick, export, read, write, list, info, grants, revoke.",
                isError: true
            )
        }
        #else
        return AgentToolResult(output: "Error: File access not available on this platform.", isError: true)
        #endif
    }

    #if canImport(UIKit)

    // MARK: - Pick

    private func handlePick(input: JSONValue) async -> AgentToolResult {
        let typeNames = input["content_types"]?.arrayValue?.compactMap { $0.stringValue } ?? ["any"]
        let multiple = input["multiple"]?.boolValue ?? false
        let contentTypes = resolveContentTypes(typeNames)

        guard let results = await FileAccessManager.shared.pickFiles(
            contentTypes: contentTypes,
            allowsMultiple: multiple
        ) else {
            return AgentToolResult(
                output: "File picker was cancelled or unavailable. Ensure FileAccessManager.configure(presentingViewController:) was called at app startup."
            )
        }

        if results.isEmpty {
            return AgentToolResult(output: "No files were selected.")
        }

        let isoFormatter = ISO8601DateFormatter()
        let columns = ["Bookmark ID", "Name", "Type", "Size", "Modified"]
        var rows: [[String]] = []

        for file in results {
            rows.append([
                file.bookmarkId,
                file.name,
                file.isDirectory ? "directory" : (file.contentType ?? "unknown"),
                file.size.map { formatFileSize($0) } ?? "-",
                file.modificationDate.map { isoFormatter.string(from: $0) } ?? "-",
            ])
        }

        let header = columns.joined(separator: " | ")
        let rowsStr = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        let output = "\(results.count) file(s) selected:\n\(header)\n\(rowsStr)"

        return AgentToolResult(output: output, details: .table(columns: columns, rows: rows))
    }

    // MARK: - Export

    private func handleExport(input: JSONValue) async -> AgentToolResult {
        guard let content = input["content"]?.stringValue else {
            return AgentToolResult(output: "Error: 'content' is required for export.", isError: true)
        }
        let filename = input["filename"]?.stringValue ?? "export.txt"

        guard let data = content.data(using: .utf8) else {
            return AgentToolResult(output: "Error: Could not encode content as UTF-8.", isError: true)
        }

        let success = await FileAccessManager.shared.exportFile(filename: filename, data: data)
        if success {
            return AgentToolResult(output: "Exported '\(filename)' (\(formatFileSize(data.count))) successfully.")
        } else {
            return AgentToolResult(output: "Export was cancelled or failed.")
        }
    }

    // MARK: - Read

    private func handleRead(input: JSONValue) async -> AgentToolResult {
        guard let bookmarkId = input["bookmark_id"]?.stringValue, !bookmarkId.isEmpty else {
            return AgentToolResult(output: "Error: 'bookmark_id' is required for read.", isError: true)
        }

        let subpath = input["path"]?.stringValue
        let fileName = await FileAccessManager.shared.fileName(for: bookmarkId, subpath: subpath) ?? "unknown"

        guard let data = await FileAccessManager.shared.readFileData(bookmarkId: bookmarkId, subpath: subpath) else {
            return AgentToolResult(
                output: "Error: Could not read file '\(fileName)'. Bookmark may be invalid or file not found.",
                isError: true
            )
        }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"]
        let displayPath = "external://\(bookmarkId)/\(subpath ?? fileName)"

        // Images — return base64
        if imageExtensions.contains(ext) {
            let base64 = data.base64EncodedString()
            return AgentToolResult(
                output: "Image: \(fileName) (\(formatFileSize(data.count)))",
                details: .file(path: displayPath, content: "[base64:\(base64)]", language: nil)
            )
        }

        // Try text
        guard let text = String(data: data, encoding: .utf8) else {
            // Binary fallback — return base64
            let base64 = data.base64EncodedString()
            return AgentToolResult(
                output: "Binary file: \(fileName) (\(formatFileSize(data.count)))",
                details: .file(path: displayPath, content: "[base64:\(base64)]", language: nil)
            )
        }

        let allLines = text.components(separatedBy: "\n")
        let startLine = max(1, input["start_line"]?.intValue ?? 1)
        let endLine = min(allLines.count, input["end_line"]?.intValue ?? allLines.count)

        guard startLine <= endLine else {
            return AgentToolResult(output: "Error: Invalid line range \(startLine)-\(endLine)", isError: true)
        }

        let selectedLines = allLines[(startLine - 1)..<endLine]
        var numberedContent = ""
        for (index, line) in selectedLines.enumerated() {
            let lineNum = startLine + index
            numberedContent += "\(lineNum)\t\(line)\n"
        }

        let language = languageForExtension(ext)
        let info = "File: \(fileName) | Lines: \(startLine)-\(endLine) of \(allLines.count) | Size: \(formatFileSize(data.count))"

        return AgentToolResult(
            output: "\(info)\n\(numberedContent)",
            details: .file(path: displayPath, content: numberedContent, language: language)
        )
    }

    // MARK: - Write

    private func handleWrite(input: JSONValue) async -> AgentToolResult {
        guard let bookmarkId = input["bookmark_id"]?.stringValue, !bookmarkId.isEmpty else {
            return AgentToolResult(output: "Error: 'bookmark_id' is required for write.", isError: true)
        }
        guard let content = input["content"]?.stringValue else {
            return AgentToolResult(output: "Error: 'content' is required for write.", isError: true)
        }

        guard let data = content.data(using: .utf8) else {
            return AgentToolResult(output: "Error: Could not encode content as UTF-8.", isError: true)
        }

        let subpath = input["path"]?.stringValue
        let success = await FileAccessManager.shared.writeFileData(bookmarkId: bookmarkId, data: data, subpath: subpath)
        if success {
            let lineCount = content.components(separatedBy: "\n").count
            let fileName = await FileAccessManager.shared.fileName(for: bookmarkId, subpath: subpath) ?? "unknown"
            return AgentToolResult(output: "Wrote \(formatFileSize(data.count)) (\(lineCount) lines) to \(fileName)")
        } else {
            return AgentToolResult(
                output: "Error: Could not write to file. Bookmark may be invalid, expired, or read-only.",
                isError: true
            )
        }
    }

    // MARK: - List

    private func handleList(input: JSONValue) async -> AgentToolResult {
        guard let bookmarkId = input["bookmark_id"]?.stringValue, !bookmarkId.isEmpty else {
            return AgentToolResult(output: "Error: 'bookmark_id' is required for list.", isError: true)
        }
        let recursive = input["recursive"]?.boolValue ?? false
        let pattern = input["pattern"]?.stringValue

        guard var entries = await FileAccessManager.shared.listDirectory(
            bookmarkId: bookmarkId,
            recursive: recursive
        ) else {
            return AgentToolResult(
                output: "Error: Could not list directory. Bookmark may be invalid or not a directory.",
                isError: true
            )
        }

        if let pattern {
            entries = entries.filter { matchesGlob(path: $0.name, pattern: pattern) }
        }

        if entries.isEmpty {
            return AgentToolResult(output: "Directory is empty or no files match the pattern.")
        }

        let isoFormatter = ISO8601DateFormatter()
        let columns = ["Name", "Type", "Size", "Content Type", "Modified"]
        var rows: [[String]] = []

        for entry in entries {
            rows.append([
                entry.isDirectory ? "\(entry.name)/" : entry.name,
                entry.isDirectory ? "dir" : "file",
                entry.size.map { formatFileSize($0) } ?? "-",
                entry.contentType ?? "-",
                entry.modificationDate.map { isoFormatter.string(from: $0) } ?? "-",
            ])
        }

        let header = columns.joined(separator: " | ")
        let rowsStr = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        let output = "\(entries.count) entries:\n\(header)\n\(rowsStr)"

        return AgentToolResult(output: output, details: .table(columns: columns, rows: rows))
    }

    // MARK: - Info

    private func handleInfo(input: JSONValue) async -> AgentToolResult {
        guard let bookmarkId = input["bookmark_id"]?.stringValue, !bookmarkId.isEmpty else {
            return AgentToolResult(output: "Error: 'bookmark_id' is required for info.", isError: true)
        }

        let subpath = input["path"]?.stringValue
        guard let info = await FileAccessManager.shared.fileInfo(bookmarkId: bookmarkId, subpath: subpath) else {
            return AgentToolResult(
                output: "Error: Could not get file info. Bookmark may be invalid or file not found.",
                isError: true
            )
        }

        let lines = info.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
        return AgentToolResult(output: lines.joined(separator: "\n"))
    }

    // MARK: - Grants

    private func handleGrants() async -> AgentToolResult {
        let grants = await FileAccessManager.shared.listGrants()

        if grants.isEmpty {
            return AgentToolResult(output: "No file access grants stored.")
        }

        let columns = ["Bookmark ID", "Name", "Valid"]
        var rows: [[String]] = []
        for grant in grants {
            rows.append([grant.id, grant.name ?? "(unknown)", grant.isValid ? "yes" : "no"])
        }

        let header = columns.joined(separator: " | ")
        let rowsStr = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        let output = "\(grants.count) grant(s):\n\(header)\n\(rowsStr)"

        return AgentToolResult(output: output, details: .table(columns: columns, rows: rows))
    }

    // MARK: - Revoke

    private func handleRevoke(input: JSONValue) async -> AgentToolResult {
        guard let bookmarkId = input["bookmark_id"]?.stringValue, !bookmarkId.isEmpty else {
            return AgentToolResult(output: "Error: 'bookmark_id' is required for revoke.", isError: true)
        }

        let success = await FileAccessManager.shared.revokeGrant(bookmarkId)
        if success {
            return AgentToolResult(output: "Revoked file access grant \(bookmarkId).")
        } else {
            return AgentToolResult(output: "Error: Bookmark ID not found.", isError: true)
        }
    }

    // MARK: - Helpers

    private func resolveContentTypes(_ typeNames: [String]) -> [UTType] {
        var types: [UTType] = []
        for name in typeNames {
            switch name.lowercased() {
            case "any", "all": types.append(.item)
            case "image", "images", "photo", "photos": types.append(.image)
            case "pdf": types.append(.pdf)
            case "text", "plaintext": types.append(.plainText)
            case "video", "movie": types.append(.movie)
            case "audio", "music", "sound": types.append(.audio)
            case "folder", "directory": types.append(.folder)
            case "spreadsheet", "excel": types.append(.spreadsheet)
            case "presentation": types.append(.presentation)
            case "archive", "zip", "compressed": types.append(.archive)
            case "json": types.append(.json)
            case "xml": types.append(.xml)
            case "html": types.append(.html)
            case "csv": types.append(.commaSeparatedText)
            case "rtf": types.append(.rtf)
            case "data", "binary": types.append(.data)
            case "source_code", "sourcecode", "code": types.append(.sourceCode)
            default:
                // Try as UTType identifier (e.g. "public.jpeg")
                if let type = UTType(name) { types.append(type) }
                // Try as file extension (e.g. "swift")
                else if let type = UTType(filenameExtension: name) { types.append(type) }
            }
        }
        return types.isEmpty ? [.item] : types
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
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

    private func matchesGlob(path: String, pattern: String) -> Bool {
        var regex = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let ch = pattern[i]
            if ch == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex && pattern[next] == "*" {
                    regex += ".*"
                    i = pattern.index(after: next)
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                } else {
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

    #endif
}
