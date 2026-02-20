import Foundation

/// Adapters transform between our generic types and provider-specific HTTP requests/responses.
public protocol ProtocolAdapter: Sendable {
    /// Build a URLRequest for the given context and model.
    func buildRequest(context: Context, model: ModelDefinition, apiKey: String) throws -> URLRequest

    /// Parse SSE stream lines into StreamEvents.
    func parseStreamEvents(lines: AsyncLineSequence<URLSession.AsyncBytes>) -> AsyncThrowingStream<StreamEvent, Error>
}
