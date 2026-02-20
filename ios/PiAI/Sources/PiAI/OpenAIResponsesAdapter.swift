import Foundation
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "OpenAIResponses")

public struct OpenAIResponsesAdapter: ProtocolAdapter {
    public init() {}

    public func buildRequest(context: Context, model: ModelDefinition, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: model.baseUrl + "/v1/responses") else {
            throw LlmError.invalidRequest("Invalid base URL: \(model.baseUrl)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "stream": .bool(true),
        ]

        if !context.systemPrompt.isEmpty {
            body["instructions"] = .string(context.systemPrompt)
        }

        // Build input array
        var input: [JSONValue] = []
        for message in context.messages {
            input.append(contentsOf: encodeMessage(message))
        }
        body["input"] = .array(input)

        // Tools
        if let tools = context.tools, !tools.isEmpty {
            let jsonTools: [JSONValue] = tools.map { tool in
                .object([
                    "type": .string("function"),
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.parameters,
                ])
            }
            body["tools"] = .array(jsonTools)
        }

        if let temp = context.temperature {
            body["temperature"] = .number(temp)
        }
        if let maxTokens = context.maxTokens {
            body["max_output_tokens"] = .number(Double(maxTokens))
        }

        let jsonData = try JSONValue.object(body).toData()
        request.httpBody = jsonData
        return request
    }

    private func encodeMessage(_ message: Message) -> [JSONValue] {
        var results: [JSONValue] = []

        switch message.role {
        case .user:
            // Emit function_call_output items for tool results
            if let toolResults = message.toolResults {
                for result in toolResults {
                    results.append(.object([
                        "type": .string("function_call_output"),
                        "call_id": .string(result.toolCallId),
                        "output": .string(result.output),
                    ]))
                }
            }

            // Only emit user message if there's actual text content
            let textContent = message.content.textValue
            if !textContent.isEmpty {
                var content: [JSONValue] = []
                switch message.content {
                case .text(let text):
                    content.append(.object(["type": .string("input_text"), "text": .string(text)]))
                case .blocks(let blocks):
                    for block in blocks {
                        switch block {
                        case .text(let text):
                            content.append(.object(["type": .string("input_text"), "text": .string(text)]))
                        case .image(let base64, let mimeType):
                            content.append(.object([
                                "type": .string("input_image"),
                                "image_url": .string("data:\(mimeType);base64,\(base64)"),
                            ]))
                        }
                    }
                }
                results.append(.object([
                    "role": .string("user"),
                    "content": .array(content),
                ]))
            }

        case .assistant:
            var content: [JSONValue] = []
            let textContent = message.content.textValue
            if !textContent.isEmpty {
                content.append(.object(["type": .string("output_text"), "text": .string(textContent)]))
            }
            if !content.isEmpty {
                results.append(.object([
                    "type": .string("message"),
                    "role": .string("assistant"),
                    "content": .array(content),
                ]))
            }

            // function_call items are top-level input items, not nested in message content
            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    results.append(.object([
                        "type": .string("function_call"),
                        "call_id": .string(call.id),
                        "name": .string(call.name),
                        "arguments": .string(call.arguments),
                        "status": .string("completed"),
                    ]))
                }
            }

            if let toolResults = message.toolResults {
                for result in toolResults {
                    results.append(.object([
                        "type": .string("function_call_output"),
                        "call_id": .string(result.toolCallId),
                        "output": .string(result.output),
                    ]))
                }
            }

        case .system:
            // System messages handled via instructions parameter
            break
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
                        let eventType = sseEvent.event
                        let data = sseEvent.data
                        guard !data.isEmpty else { continue }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
                        else { continue }

                        switch eventType {
                        case "response.output_text.delta":
                            if let delta = json["delta"]?.stringValue {
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.function_call_arguments.delta":
                            if let delta = json["delta"]?.stringValue,
                               let itemId = json["item_id"]?.stringValue {
                                continuation.yield(.toolCallDelta(id: itemId, argumentsDelta: delta))
                            }

                        case "response.output_item.added":
                            if let item = json["item"],
                               let itemType = item["type"]?.stringValue,
                               itemType == "function_call",
                               let id = item["id"]?.stringValue,
                               let name = item["name"]?.stringValue {
                                continuation.yield(.toolCallStart(id: id, name: name))
                            }

                        case "response.function_call_arguments.done":
                            if let itemId = json["item_id"]?.stringValue {
                                continuation.yield(.toolCallEnd(id: itemId))
                            }

                        case "response.completed":
                            if let response = json["response"],
                               let usage = response["usage"] {
                                let input = usage["input_tokens"]?.intValue ?? 0
                                let output = usage["output_tokens"]?.intValue ?? 0
                                continuation.yield(.usage(inputTokens: input, outputTokens: output))
                            }

                        case "error":
                            let message = json["error"]?["message"]?.stringValue ?? "Unknown error"
                            logger.error("[OpenAI-Resp] Error: \(message)")
                            continuation.yield(.error(message))

                        default:
                            break
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    logger.error("[OpenAI-Resp] Stream error: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
