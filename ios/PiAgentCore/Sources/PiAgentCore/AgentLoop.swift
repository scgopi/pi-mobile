import Foundation
import PiAI
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "AgentLoop")

public final class AgentLoop: Sendable {
    private let llmClient: LlmClient
    private let validator: SchemaValidator

    public init(llmClient: LlmClient) {
        self.llmClient = llmClient
        self.validator = SchemaValidator()
    }

    /// Run the agent loop: stream a response, execute tool calls, repeat until done.
    public func run(
        model: ModelDefinition,
        context: inout Context,
        tools: [any Tool],
        apiKey: String,
        maxIterations: Int = 20
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        // Capture context as a let copy; mutability moves inside the Task.
        var localContext = context
        localContext.tools = tools.map { tool in
            ToolDefinition(name: tool.name, description: tool.description, parameters: tool.parametersSchema)
        }
        let capturedContext = localContext
        let client = self.llmClient
        let validator = self.validator

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var localContext = capturedContext
                    var iteration = 0

                    while iteration < maxIterations {
                        iteration += 1
                        logger.debug("[AgentLoop] Iteration \(iteration)/\(maxIterations)")

                        // Stream response from LLM
                        var fullText = ""
                        var fullThinking = ""
                        var pendingToolCalls: [ToolCall] = []
                        var currentToolCallArgs: [String: String] = [:]

                        let stream = client.stream(model: model, context: localContext, apiKey: apiKey)

                        for try await event in stream {
                            switch event {
                            case .textDelta(let delta):
                                fullText += delta
                                continuation.yield(.streamDelta(delta))

                            case .thinkingDelta(let delta):
                                fullThinking += delta
                                continuation.yield(.thinkingDelta(delta))

                            case .toolCallStart(let id, let name):
                                currentToolCallArgs[id] = ""
                                logger.info("[AgentLoop] Tool call started: \(name) (id=\(id))")
                                continuation.yield(.toolCallStarted(name: name, input: .null))
                                pendingToolCalls.append(ToolCall(id: id, name: name, arguments: ""))

                            case .toolCallDelta(let id, let argsDelta):
                                currentToolCallArgs[id, default: ""] += argsDelta

                            case .toolCallEnd(let id):
                                if let index = pendingToolCalls.firstIndex(where: { $0.id == id }) {
                                    let args = currentToolCallArgs[id] ?? "{}"
                                    pendingToolCalls[index] = ToolCall(
                                        id: pendingToolCalls[index].id,
                                        name: pendingToolCalls[index].name,
                                        arguments: args
                                    )
                                    logger.info("[AgentLoop] Tool call complete: \(pendingToolCalls[index].name) args=\(args.prefix(500))")
                                }

                            case .usage(let input, let output):
                                continuation.yield(.usageUpdate(inputTokens: input, outputTokens: output))

                            case .done:
                                break

                            case .error(let message):
                                logger.error("[AgentLoop] Stream error: \(message)")
                                continuation.yield(.error(message))
                            }
                        }

                        logger.info("[AgentLoop] LLM response: \(fullText.count) chars, \(pendingToolCalls.count) tool call(s)")
                        if !fullText.isEmpty {
                            logger.debug("[AgentLoop] Response text: \(fullText.prefix(500))")
                        }

                        // Emit full assistant message
                        let thinking: String? = fullThinking.isEmpty ? nil : fullThinking
                        continuation.yield(.assistantMessage(content: fullText, thinking: thinking))

                        // If no tool calls, we're done
                        if pendingToolCalls.isEmpty {
                            localContext.messages.append(Message(
                                role: .assistant,
                                content: .text(fullText),
                                thinking: thinking
                            ))
                            break
                        }

                        // Execute tool calls
                        logger.info("[AgentLoop] Executing \(pendingToolCalls.count) tool call(s)")
                        var toolResults: [ToolResult] = []
                        for toolCall in pendingToolCalls {
                            let result = await executeTool(toolCall, tools: tools, validator: validator)
                            logger.info("[AgentLoop] Tool result [\(toolCall.name)]: isError=\(result.isError) output=\(result.output.prefix(300))")
                            continuation.yield(.toolCallCompleted(name: toolCall.name, result: result))
                            toolResults.append(ToolResult(
                                toolCallId: result.toolCallId,
                                output: result.output,
                                isError: result.isError
                            ))
                        }

                        // Append assistant message + tool results to context
                        localContext.messages.append(Message(
                            role: .assistant,
                            content: .text(fullText),
                            toolCalls: pendingToolCalls,
                            thinking: thinking
                        ))
                        localContext.messages.append(Message(
                            role: .user,
                            content: .text(""),
                            toolResults: toolResults
                        ))
                    }

                    if iteration >= maxIterations {
                        logger.warning("[AgentLoop] Hit max iterations (\(maxIterations))")
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    logger.error("[AgentLoop] Error: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func executeTool(_ call: ToolCall, tools: [any Tool], validator: SchemaValidator) async -> AgentToolResult {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return AgentToolResult(
                toolCallId: call.id,
                output: "Error: Unknown tool '\(call.name)'",
                details: .error(message: "Unknown tool", code: "UNKNOWN_TOOL"),
                isError: true
            )
        }

        // Parse arguments
        let input = call.input

        // Validate against schema
        let validation = validator.validate(input, against: tool.parametersSchema)
        if !validation.isValid {
            let errorMessages = validation.errors.map { $0.localizedDescription }.joined(separator: "; ")
            return AgentToolResult(
                toolCallId: call.id,
                output: "Validation error: \(errorMessages)",
                details: .error(message: errorMessages, code: "VALIDATION_ERROR"),
                isError: true
            )
        }

        do {
            let result = try await tool.execute(input: input)
            return AgentToolResult(
                toolCallId: call.id,
                output: result.output,
                details: result.details,
                isError: result.isError
            )
        } catch {
            logger.error("[AgentLoop] Tool '\(call.name)' error: \(error.localizedDescription)")
            return AgentToolResult(
                toolCallId: call.id,
                output: "Error executing tool '\(call.name)': \(error.localizedDescription)",
                details: .error(message: error.localizedDescription, code: "EXECUTION_ERROR"),
                isError: true
            )
        }
    }
}
