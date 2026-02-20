import Foundation

/// Adapter for Azure OpenAI Service.
///
/// Azure uses the same wire format as OpenAI (Responses API) but with:
/// - `baseUrl` as the full endpoint URL (e.g. `https://{resource}.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview`)
/// - `api-key` header instead of `Authorization: Bearer`
public struct AzureOpenAIAdapter: ProtocolAdapter {
    private let responsesAdapter = OpenAIResponsesAdapter()

    public init() {}

    public func buildRequest(context: Context, model: ModelDefinition, apiKey: String) throws -> URLRequest {
        // Azure baseUrl is the full endpoint URL including path and api-version
        guard let url = URL(string: model.baseUrl) else {
            throw LlmError.invalidRequest("Invalid Azure endpoint URL: \(model.baseUrl)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")

        // Body format is identical to OpenAI Responses API
        var body: [String: JSONValue] = [
            "model": .string(model.id),
            "stream": .bool(true),
        ]

        if !context.systemPrompt.isEmpty {
            body["instructions"] = .string(context.systemPrompt)
        }

        var input: [JSONValue] = []
        for message in context.messages {
            input.append(contentsOf: encodeMessage(message))
        }
        body["input"] = .array(input)

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

        if let temp = context.temperature, !model.capabilities.reasoning {
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
            break
        }

        return results
    }

    // Response parsing is identical to OpenAI Responses API
    public func parseStreamEvents(lines: AsyncLineSequence<URLSession.AsyncBytes>) -> AsyncThrowingStream<StreamEvent, Error> {
        responsesAdapter.parseStreamEvents(lines: lines)
    }
}
