import Foundation
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "LlmClient")

public final class LlmClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Stream a response from the given model.
    public func stream(model: ModelDefinition, context: Context, apiKey: String) -> AsyncThrowingStream<StreamEvent, Error> {
        let adapter = Self.getAdapter(for: model.protocolType)

        let request: URLRequest
        do {
            request = try adapter.buildRequest(context: context, model: model, apiKey: apiKey)
            logger.debug("[LlmClient] Request → \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "nil")")
        } catch {
            logger.error("[LlmClient] Failed to build request: \(error.localizedDescription)")
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let urlSession = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LlmError.networkError(
                            NSError(domain: "LlmClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
                        ))
                        return
                    }

                    logger.debug("[LlmClient] HTTP \(httpResponse.statusCode)")

                    guard (200...299).contains(httpResponse.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line + "\n"
                        }
                        logger.error("[LlmClient] HTTP error \(httpResponse.statusCode): \(body.prefix(500))")
                        continuation.finish(throwing: LlmError.httpError(statusCode: httpResponse.statusCode, body: body))
                        return
                    }

                    let eventStream = adapter.parseStreamEvents(lines: bytes.lines)
                    for try await event in eventStream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    logger.error("[LlmClient] Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: LlmError.networkError(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Get the appropriate protocol adapter for a wire protocol.
    public static func getAdapter(for protocolType: WireProtocol) -> ProtocolAdapter {
        switch protocolType {
        case .openaiCompletions:
            return OpenAICompletionsAdapter()
        case .openaiResponses:
            return OpenAIResponsesAdapter()
        case .anthropic:
            return AnthropicAdapter()
        case .google:
            return GoogleAdapter()
        case .azure:
            return AzureOpenAIAdapter()
        }
    }
}
