import Foundation
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "GoogleAdapter")

public struct GoogleAdapter: ProtocolAdapter {
    public init() {}

    public func buildRequest(context: Context, model: ModelDefinition, apiKey: String) throws -> URLRequest {
        let urlString = "\(model.baseUrl)/v1beta/models/\(model.id):streamGenerateContent?alt=sse&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw LlmError.invalidRequest("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: JSONValue] = [:]

        // System instruction
        if !context.systemPrompt.isEmpty {
            body["system_instruction"] = .object([
                "parts": .array([.object(["text": .string(context.systemPrompt)])])
            ])
        }

        // Contents
        var contents: [JSONValue] = []
        for message in context.messages {
            contents.append(contentsOf: encodeMessage(message))
        }
        body["contents"] = .array(contents)

        // Tools
        if let tools = context.tools, !tools.isEmpty {
            let functionDeclarations: [JSONValue] = tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.parameters,
                ])
            }
            body["tools"] = .array([
                .object(["function_declarations": .array(functionDeclarations)])
            ])
        }

        // Generation config
        var generationConfig: [String: JSONValue] = [:]
        if let temp = context.temperature {
            generationConfig["temperature"] = .number(temp)
        }
        if let maxTokens = context.maxTokens {
            generationConfig["maxOutputTokens"] = .number(Double(maxTokens))
        }
        if !generationConfig.isEmpty {
            body["generationConfig"] = .object(generationConfig)
        }

        let jsonData = try JSONValue.object(body).toData()
        request.httpBody = jsonData
        return request
    }

    private func encodeMessage(_ message: Message) -> [JSONValue] {
        var results: [JSONValue] = []

        let role: String
        switch message.role {
        case .user: role = "user"
        case .assistant: role = "model"
        case .system: return [] // Handled via system_instruction
        }

        var parts: [JSONValue] = []

        switch message.content {
        case .text(let text):
            if !text.isEmpty {
                parts.append(.object(["text": .string(text)]))
            }
        case .blocks(let blocks):
            for block in blocks {
                switch block {
                case .text(let text):
                    parts.append(.object(["text": .string(text)]))
                case .image(let base64, let mimeType):
                    parts.append(.object([
                        "inline_data": .object([
                            "mime_type": .string(mimeType),
                            "data": .string(base64),
                        ])
                    ]))
                }
            }
        }

        // Tool calls (function calls from assistant)
        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                var argsJson: JSONValue = .object([:])
                if let data = call.arguments.data(using: .utf8) {
                    argsJson = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
                }
                parts.append(.object([
                    "functionCall": .object([
                        "name": .string(call.name),
                        "args": argsJson,
                    ])
                ]))
            }
        }

        if !parts.isEmpty {
            results.append(.object([
                "role": .string(role),
                "parts": .array(parts),
            ]))
        }

        // Tool results as a separate user turn
        if let toolResults = message.toolResults, !toolResults.isEmpty {
            var responseParts: [JSONValue] = []
            for result in toolResults {
                responseParts.append(.object([
                    "functionResponse": .object([
                        "name": .string(result.toolCallId),
                        "response": .object([
                            "result": .string(result.output),
                        ]),
                    ])
                ]))
            }
            results.append(.object([
                "role": .string("user"),
                "parts": .array(responseParts),
            ]))
        }

        return results
    }

    public func parseStreamEvents(lines: AsyncLineSequence<URLSession.AsyncBytes>) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var sseParser = SSELineParser()

                    for try await line in lines {
                        guard let sseEvent = sseParser.feedLine(line) else { continue }
                        let data = sseEvent.data
                        guard !data.isEmpty else { continue }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
                        else { continue }

                        // Check for error
                        if let error = json["error"]?["message"]?.stringValue {
                            logger.error("[Google] Stream error: \(error)")
                            continuation.yield(.error(error))
                            continue
                        }

                        // Parse candidates[0].content.parts
                        if let parts = json["candidates"]?[0]?["content"]?["parts"]?.arrayValue {
                            for part in parts {
                                if let text = part["text"]?.stringValue {
                                    continuation.yield(.textDelta(text))
                                }

                                if let functionCall = part["functionCall"] {
                                    let name = functionCall["name"]?.stringValue ?? ""
                                    let id = name + "_" + UUID().uuidString.prefix(8).lowercased()
                                    continuation.yield(.toolCallStart(id: id, name: name))

                                    if let args = functionCall["args"] {
                                        let argsString = (try? args.toJSONString()) ?? "{}"
                                        continuation.yield(.toolCallDelta(id: id, argumentsDelta: argsString))
                                    }

                                    continuation.yield(.toolCallEnd(id: id))
                                }
                            }
                        }

                        // Usage metadata
                        if let usageMetadata = json["usageMetadata"] {
                            let input = usageMetadata["promptTokenCount"]?.intValue ?? 0
                            let output = usageMetadata["candidatesTokenCount"]?.intValue ?? 0
                            continuation.yield(.usage(inputTokens: input, outputTokens: output))
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    logger.error("[Google] Stream error: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
