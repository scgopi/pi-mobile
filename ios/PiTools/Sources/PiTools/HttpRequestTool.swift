import Foundation
import PiAgentCore
import PiAI

public struct HttpRequestTool: Tool, Sendable {
    public let name = "http_request"
    public let description = "Make HTTP requests. Returns status code, response headers, and body."

    public init() {}

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("url")]),
            "properties": .object([
                "url": .object([
                    "type": .string("string"),
                    "description": .string("The URL to request"),
                ]),
                "method": .object([
                    "type": .string("string"),
                    "description": .string("HTTP method (GET, POST, PUT, DELETE, PATCH). Defaults to GET."),
                    "enum": .array([.string("GET"), .string("POST"), .string("PUT"), .string("DELETE"), .string("PATCH")]),
                ]),
                "headers": .object([
                    "type": .string("object"),
                    "description": .string("Request headers as key-value pairs"),
                ]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string("Request body (for POST, PUT, PATCH)"),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        guard let urlString = input["url"]?.stringValue else {
            return AgentToolResult(output: "Error: 'url' parameter is required", isError: true)
        }
        guard let url = URL(string: urlString) else {
            return AgentToolResult(output: "Error: Invalid URL: \(urlString)", isError: true)
        }

        let method = input["method"]?.stringValue ?? "GET"

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        // Set headers
        if let headers = input["headers"]?.objectValue {
            for (key, value) in headers {
                if let strValue = value.stringValue {
                    request.setValue(strValue, forHTTPHeaderField: key)
                }
            }
        }

        // Set body
        if let body = input["body"]?.stringValue {
            request.httpBody = body.data(using: .utf8)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return AgentToolResult(output: "Error: Invalid response type", isError: true)
            }

            let statusCode = httpResponse.statusCode

            // Format headers
            var headerLines: [String] = []
            for (key, value) in httpResponse.allHeaderFields {
                headerLines.append("\(key): \(value)")
            }
            let headersStr = headerLines.sorted().joined(separator: "\n")

            // Response body
            let bodyStr = String(data: data, encoding: .utf8) ?? "[Binary data: \(data.count) bytes]"

            // Truncate large responses
            let truncatedBody: String
            if bodyStr.count > 10000 {
                truncatedBody = String(bodyStr.prefix(10000)) + "\n... (truncated, \(bodyStr.count) total chars)"
            } else {
                truncatedBody = bodyStr
            }

            let output = """
                Status: \(statusCode)

                Headers:
                \(headersStr)

                Body:
                \(truncatedBody)
                """

            return AgentToolResult(output: output, isError: statusCode >= 400)
        } catch {
            return AgentToolResult(output: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}
