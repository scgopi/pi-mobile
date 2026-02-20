import Foundation
import PiAgentCore
import PiAI

/// A tool defined by a JSON file with a name, description, parameters schema, and a simple HTTP action.
public struct JsonDefinedTool: Tool {
    public let name: String
    public let description: String
    public let parametersSchema: JSONValue
    private let actionUrl: String
    private let actionMethod: String
    private let actionHeaders: [String: String]

    public init(
        name: String,
        description: String,
        parametersSchema: JSONValue,
        actionUrl: String,
        actionMethod: String = "POST",
        actionHeaders: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
        self.actionUrl = actionUrl
        self.actionMethod = actionMethod
        self.actionHeaders = actionHeaders
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        guard let url = URL(string: actionUrl) else {
            return AgentToolResult(output: "Invalid action URL: \(actionUrl)", isError: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = actionMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in actionHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = try input.toData()
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseBody = String(data: data, encoding: .utf8) ?? ""

        if (200...299).contains(statusCode) {
            return AgentToolResult(output: responseBody)
        } else {
            return AgentToolResult(output: "HTTP \(statusCode): \(responseBody)", isError: true)
        }
    }
}

/// Loads tool definitions from JSON files and creates a simple extension.
public struct JsonExtensionLoader: Sendable {
    public init() {}

    /// Load tool definitions from a JSON file.
    /// Expected format:
    /// ```json
    /// {
    ///   "id": "my-extension",
    ///   "name": "My Extension",
    ///   "description": "Does things",
    ///   "tools": [
    ///     {
    ///       "name": "my_tool",
    ///       "description": "A tool",
    ///       "parameters": { ... },
    ///       "action": { "url": "https://...", "method": "POST", "headers": {} }
    ///     }
    ///   ]
    /// }
    /// ```
    public func load(from data: Data) throws -> any PiExtension {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)

        guard let obj = json.objectValue,
              let id = obj["id"]?.stringValue,
              let name = obj["name"]?.stringValue
        else {
            throw JsonExtensionError.invalidFormat("Missing required fields: id, name")
        }

        let description = obj["description"]?.stringValue ?? ""
        var tools: [any Tool] = []

        if let toolDefs = obj["tools"]?.arrayValue {
            for toolDef in toolDefs {
                guard let toolObj = toolDef.objectValue,
                      let toolName = toolObj["name"]?.stringValue,
                      let toolDescription = toolObj["description"]?.stringValue
                else { continue }

                let parameters = toolObj["parameters"] ?? .object(["type": "object", "properties": .object([:])])
                let action = toolObj["action"]?.objectValue ?? [:]
                let actionUrl = action["url"]?.stringValue ?? ""
                let actionMethod = action["method"]?.stringValue ?? "POST"
                var actionHeaders: [String: String] = [:]
                if let headers = action["headers"]?.objectValue {
                    for (key, value) in headers {
                        if let strValue = value.stringValue {
                            actionHeaders[key] = strValue
                        }
                    }
                }

                tools.append(JsonDefinedTool(
                    name: toolName,
                    description: toolDescription,
                    parametersSchema: parameters,
                    actionUrl: actionUrl,
                    actionMethod: actionMethod,
                    actionHeaders: actionHeaders
                ))
            }
        }

        return LoadedExtension(id: id, name: name, description: description, tools: tools)
    }

    public func load(from url: URL) throws -> any PiExtension {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }
}

public enum JsonExtensionError: Error, LocalizedError {
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid extension format: \(message)"
        }
    }
}

/// An extension loaded from JSON.
private struct LoadedExtension: PiExtension {
    let id: String
    let name: String
    let description: String
    let tools: [any Tool]
}
