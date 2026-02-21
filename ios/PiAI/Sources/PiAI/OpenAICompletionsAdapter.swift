import Foundation
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "OpenAICompletions")

public struct OpenAICompletionsAdapter: ProtocolAdapter {
    public init() {}

    public func buildRequest(context: Context, model: ModelDefinition, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: model.baseUrl + "/v1/chat/completions") else {
            throw LlmError.invalidRequest("Invalid base URL: \(model.baseUrl)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "stream": .bool(true),
            "stream_options": .object(["include_usage": .bool(true)]),
        ]

        // Messages
        var jsonMessages: [JSONValue] = []

        if !context.systemPrompt.isEmpty {
            jsonMessages.append(.object([
                "role": .string("system"),
                "content": .string(context.systemPrompt),
            ]))
        }

        for message in context.messages {
            let jsonMessage = encodeMessage(message)
            jsonMessages.append(contentsOf: jsonMessage)
        }
        body["messages"] = .array(jsonMessages)

        // Tools
        if let tools = context.tools, !tools.isEmpty {
            let jsonTools: [JSONValue] = tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.parameters,
                    ]),
                ])
            }
            body["tools"] = .array(jsonTools)
        }

        if let temp = context.temperature {
            body["temperature"] = .number(temp)
        }
        if let maxTokens = context.maxTokens {
            if model.capabilities.reasoning {
                body["max_completion_tokens"] = .number(Double(maxTokens))
            } else {
                body["max_tokens"] = .number(Double(maxTokens))
            }
        }

        #if DEBUG
        if let jsonData = try? JSONValue.object(body).toData(),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let redacted = jsonString.replacingOccurrences(
                of: "data:image\\/[^;]+;base64,[A-Za-z0-9+/=]+",
                with: "<IMAGE_DATA_REDACTED>",
                options: .regularExpression
            )
            logger.debug("[OpenAICompletions] Request body:\n\(redacted)")
        }
        #endif

        let jsonData = try JSONValue.object(body).toData()
        request.httpBody = jsonData
        return request
    }

    private func encodeMessage(_ message: Message) -> [JSONValue] {
        var results: [JSONValue] = []

        switch message.role {
        case .user:
            // Tool results are sent as separate "tool" role messages
            if let toolResults = message.toolResults {
                for result in toolResults {
                    results.append(.object([
                        "role": .string("tool"),
                        "tool_call_id": .string(result.toolCallId),
                        "content": .string(result.output),
                    ]))
                }
            }

            // Only emit user message if there's actual text content
            let textContent = message.content.textValue
            if !textContent.isEmpty {
                let content = encodeContent(message.content)
                results.append(.object([
                    "role": .string("user"),
                    "content": content,
                ]))
            }
        case .assistant:
            var msgObj: [String: JSONValue] = [
                "role": .string("assistant"),
            ]

            let textContent = message.content.textValue
            if !textContent.isEmpty {
                msgObj["content"] = .string(textContent)
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                let jsonCalls: [JSONValue] = toolCalls.map { call in
                    .object([
                        "id": .string(call.id),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.name),
                            "arguments": .string(call.arguments),
                        ]),
                    ])
                }
                msgObj["tool_calls"] = .array(jsonCalls)
            }

            results.append(.object(msgObj))

            // Tool results follow as separate messages
            if let toolResults = message.toolResults {
                for result in toolResults {
                    results.append(.object([
                        "role": .string("tool"),
                        "tool_call_id": .string(result.toolCallId),
                        "content": .string(result.output),
                    ]))
                }
            }
        case .system:
            let content = encodeContent(message.content)
            results.append(.object([
                "role": .string("system"),
                "content": content,
            ]))
        }

        return results
    }

    private func encodeContent(_ content: MessageContent) -> JSONValue {
        switch content {
        case .text(let text):
            return .string(text)
        case .blocks(let blocks):
            let jsonBlocks: [JSONValue] = blocks.map { block in
                switch block {
                case .text(let text):
                    return .object(["type": .string("text"), "text": .string(text)])
                case .image(let base64, let mimeType):
                    return .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:\(mimeType);base64,\(base64)"),
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
                    var activeToolCalls: [Int: (id: String, name: String)] = [:]
                    #if DEBUG
                    var lineCount = 0
                    var eventCount = 0
                    #endif

                    for try await line in lines {
                        #if DEBUG
                        lineCount += 1
                        if lineCount <= 20 || lineCount % 50 == 0 {
                            let preview = line.count > 300 ? String(line.prefix(300)) + "..." : line
                            logger.debug("[OpenAI] SSE line \(lineCount): \(preview)")
                        }
                        #endif
                        guard let sseEvent = sseParser.feedLine(line) else { continue }
                        let data = sseEvent.data
                        guard !data.isEmpty else { continue }
                        #if DEBUG
                        eventCount += 1
                        let dataPreview = data.count > 500 ? String(data.prefix(500)) + "..." : data
                        logger.debug("[OpenAI] SSE event \(eventCount): \(dataPreview)")
                        #endif

                        guard let jsonData = data.data(using: .utf8),
                              let json = try? JSONDecoder().decode(JSONValue.self, from: jsonData)
                        else {
                            #if DEBUG
                            logger.warning("[OpenAI] Failed to parse JSON from SSE data: \(data.prefix(200))")
                            #endif
                            continue
                        }

                        // Check for error
                        if let error = json["error"]?["message"]?.stringValue {
                            logger.error("[OpenAI] Stream error: \(error)")
                            continuation.yield(.error(error))
                            continue
                        }

                        // Parse choices[0].delta
                        guard let delta = json["choices"]?[0]?["delta"] else {
                            if let usage = json["usage"] {
                                if let input = usage["prompt_tokens"]?.intValue,
                                   let output = usage["completion_tokens"]?.intValue {
                                    continuation.yield(.usage(inputTokens: input, outputTokens: output))
                                }
                            }
                            continue
                        }

                        // Text content
                        if let content = delta["content"]?.stringValue {
                            continuation.yield(.textDelta(content))
                        }

                        // Reasoning / thinking content
                        if let reasoning = delta["reasoning_content"]?.stringValue {
                            continuation.yield(.thinkingDelta(reasoning))
                        }

                        // Tool calls
                        if let toolCalls = delta["tool_calls"]?.arrayValue {
                            for toolCallJson in toolCalls {
                                guard let index = toolCallJson["index"]?.intValue else { continue }

                                if let function = toolCallJson["function"] {
                                    if let id = toolCallJson["id"]?.stringValue,
                                       let name = function["name"]?.stringValue {
                                        activeToolCalls[index] = (id: id, name: name)
                                        continuation.yield(.toolCallStart(id: id, name: name))
                                    }

                                    if let args = function["arguments"]?.stringValue,
                                       let callInfo = activeToolCalls[index] {
                                        continuation.yield(.toolCallDelta(id: callInfo.id, argumentsDelta: args))
                                    }
                                }
                            }
                        }

                        // Finish reason
                        if let finishReason = json["choices"]?[0]?["finish_reason"]?.stringValue,
                           finishReason == "tool_calls" || finishReason == "stop" {
                            for (_, callInfo) in activeToolCalls.sorted(by: { $0.key < $1.key }) {
                                continuation.yield(.toolCallEnd(id: callInfo.id))
                            }
                            activeToolCalls.removeAll()
                        }

                        // Usage
                        if let usage = json["usage"] {
                            if let input = usage["prompt_tokens"]?.intValue,
                               let output = usage["completion_tokens"]?.intValue {
                                continuation.yield(.usage(inputTokens: input, outputTokens: output))
                            }
                        }
                    }

                    #if DEBUG
                    logger.debug("[OpenAI] Stream loop ended. Total lines=\(lineCount), events=\(eventCount)")
                    #endif

                    // Flush remaining SSE buffer
                    if let remaining = sseParser.flush() {
                        if let jsonData = remaining.data.data(using: .utf8),
                           let json = try? JSONDecoder().decode(JSONValue.self, from: jsonData),
                           let usage = json["usage"] {
                            if let input = usage["prompt_tokens"]?.intValue,
                               let output = usage["completion_tokens"]?.intValue {
                                continuation.yield(.usage(inputTokens: input, outputTokens: output))
                            }
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    logger.error("[OpenAI] Stream error: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
