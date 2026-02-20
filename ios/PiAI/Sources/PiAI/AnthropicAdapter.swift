import Foundation
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "AnthropicAdapter")

public struct AnthropicAdapter: ProtocolAdapter {
    public init() {}

    public func buildRequest(context: Context, model: ModelDefinition, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: model.baseUrl + "/v1/messages") else {
            throw LlmError.invalidRequest("Invalid base URL: \(model.baseUrl)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "stream": .bool(true),
        ]

        if !context.systemPrompt.isEmpty {
            body["system"] = .string(context.systemPrompt)
        }

        // Messages
        var jsonMessages: [JSONValue] = []
        for message in context.messages {
            jsonMessages.append(contentsOf: encodeMessage(message))
        }
        body["messages"] = .array(jsonMessages)

        // Tools
        if let tools = context.tools, !tools.isEmpty {
            let jsonTools: [JSONValue] = tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.parameters,
                ])
            }
            body["tools"] = .array(jsonTools)
        }

        if let temp = context.temperature {
            body["temperature"] = .number(temp)
        }
        body["max_tokens"] = .number(Double(context.maxTokens ?? model.maxOutputTokens))

        let jsonData = try JSONValue.object(body).toData()
        request.httpBody = jsonData
        return request
    }

    private func encodeMessage(_ message: Message) -> [JSONValue] {
        var results: [JSONValue] = []

        switch message.role {
        case .user:
            let content = encodeContent(message.content)
            var userMsg: [String: JSONValue] = [
                "role": .string("user"),
                "content": content,
            ]

            // If there are tool results, encode them as part of user message
            if let toolResults = message.toolResults, !toolResults.isEmpty {
                var blocks: [JSONValue] = []
                for result in toolResults {
                    blocks.append(.object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string(result.toolCallId),
                        "content": .string(result.output),
                        "is_error": .bool(result.isError),
                    ]))
                }
                userMsg["content"] = .array(blocks)
            }

            results.append(.object(userMsg))

        case .assistant:
            var content: [JSONValue] = []
            let textContent = message.content.textValue
            if !textContent.isEmpty {
                content.append(.object([
                    "type": .string("text"),
                    "text": .string(textContent),
                ]))
            }

            if let thinking = message.thinking, !thinking.isEmpty {
                content.insert(.object([
                    "type": .string("thinking"),
                    "thinking": .string(thinking),
                ]), at: 0)
            }

            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    var inputJson: JSONValue = .object([:])
                    if let data = call.arguments.data(using: .utf8) {
                        inputJson = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
                    }
                    content.append(.object([
                        "type": .string("tool_use"),
                        "id": .string(call.id),
                        "name": .string(call.name),
                        "input": inputJson,
                    ]))
                }
            }

            results.append(.object([
                "role": .string("assistant"),
                "content": .array(content),
            ]))

            // Tool results go in a separate user message for Anthropic
            if let toolResults = message.toolResults, !toolResults.isEmpty {
                var blocks: [JSONValue] = []
                for result in toolResults {
                    blocks.append(.object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string(result.toolCallId),
                        "content": .string(result.output),
                        "is_error": .bool(result.isError),
                    ]))
                }
                results.append(.object([
                    "role": .string("user"),
                    "content": .array(blocks),
                ]))
            }

        case .system:
            // System handled via top-level system parameter
            break
        }

        return results
    }

    private func encodeContent(_ content: MessageContent) -> JSONValue {
        switch content {
        case .text(let text):
            return .array([.object(["type": .string("text"), "text": .string(text)])])
        case .blocks(let blocks):
            let jsonBlocks: [JSONValue] = blocks.map { block in
                switch block {
                case .text(let text):
                    return .object(["type": .string("text"), "text": .string(text)])
                case .image(let base64, let mimeType):
                    return .object([
                        "type": .string("image"),
                        "source": .object([
                            "type": .string("base64"),
                            "media_type": .string(mimeType),
                            "data": .string(base64),
                        ]),
                    ])
                }
            }
            return .array(jsonBlocks)
        }
    }

    public func parseStreamEvents(lines: AsyncLineSequence<URLSession.AsyncBytes>) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var sseParser = SSELineParser()
                    var currentContentBlockType: String?
                    var currentToolCallId: String?

                    for try await line in lines {
                        guard let sseEvent = sseParser.feedLine(line) else { continue }
                        let eventType = sseEvent.event ?? ""
                        let data = sseEvent.data
                        guard !data.isEmpty else { continue }

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
                        else { continue }

                        switch eventType {
                        case "message_start":
                            if let usage = json["message"]?["usage"] {
                                let input = usage["input_tokens"]?.intValue ?? 0
                                continuation.yield(.usage(inputTokens: input, outputTokens: 0))
                            }

                        case "content_block_start":
                            if let contentBlock = json["content_block"] {
                                let blockType = contentBlock["type"]?.stringValue ?? ""
                                currentContentBlockType = blockType

                                if blockType == "tool_use" {
                                    let id = contentBlock["id"]?.stringValue ?? ""
                                    let name = contentBlock["name"]?.stringValue ?? ""
                                    currentToolCallId = id
                                    continuation.yield(.toolCallStart(id: id, name: name))
                                }
                            }

                        case "content_block_delta":
                            if let delta = json["delta"] {
                                let deltaType = delta["type"]?.stringValue ?? ""

                                switch deltaType {
                                case "text_delta":
                                    if let text = delta["text"]?.stringValue {
                                        continuation.yield(.textDelta(text))
                                    }
                                case "thinking_delta":
                                    if let thinking = delta["thinking"]?.stringValue {
                                        continuation.yield(.thinkingDelta(thinking))
                                    }
                                case "input_json_delta":
                                    if let partialJson = delta["partial_json"]?.stringValue,
                                       let toolId = currentToolCallId {
                                        continuation.yield(.toolCallDelta(id: toolId, argumentsDelta: partialJson))
                                    }
                                default:
                                    break
                                }
                            }

                        case "content_block_stop":
                            if currentContentBlockType == "tool_use", let toolId = currentToolCallId {
                                continuation.yield(.toolCallEnd(id: toolId))
                                currentToolCallId = nil
                            }
                            currentContentBlockType = nil

                        case "message_delta":
                            if let usage = json["usage"] {
                                let output = usage["output_tokens"]?.intValue ?? 0
                                continuation.yield(.usage(inputTokens: 0, outputTokens: output))
                            }

                        case "message_stop":
                            break

                        case "error":
                            let message = json["error"]?["message"]?.stringValue ?? "Unknown Anthropic error"
                            logger.error("[Anthropic] Stream error: \(message)")
                            continuation.yield(.error(message))

                        default:
                            break
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    logger.error("[Anthropic] Stream error: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
