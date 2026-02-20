import Foundation
import os

private let logger = Logger(subsystem: "com.pi.ai", category: "SSEParser")

public struct SSEEvent: Sendable {
    public let event: String?
    public let data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

public struct SSEParser: Sendable {
    public init() {}

    /// Parse a complete line from an SSE stream.
    /// Returns nil for comment lines, empty lines, or incomplete events.
    public static func parse(line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else { return nil }

        if trimmed.hasPrefix("data: ") {
            let data = String(trimmed.dropFirst(6))
            if data == "[DONE]" { return nil }
            return SSEEvent(event: nil, data: data)
        }

        if trimmed.hasPrefix("data:") {
            let data = String(trimmed.dropFirst(5))
            if data == "[DONE]" { return nil }
            return SSEEvent(event: nil, data: data)
        }

        if trimmed.hasPrefix("event: ") {
            let eventName = String(trimmed.dropFirst(7))
            return SSEEvent(event: eventName, data: "")
        }

        if trimmed.hasPrefix("event:") {
            let eventName = String(trimmed.dropFirst(6))
            return SSEEvent(event: eventName, data: "")
        }

        return nil
    }
}

/// An async SSE line parser that buffers and accumulates event+data pairs from URLSession.AsyncBytes
public struct SSELineParser {
    private var currentEvent: String?
    private var dataBuffer: [String] = []

    public init() {}

    /// Feed a line and get back a complete SSEEvent if one is ready
    public mutating func feedLine(_ line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty line = dispatch event
        if trimmed.isEmpty {
            if !dataBuffer.isEmpty {
                let data = dataBuffer.joined(separator: "\n")
                let event = SSEEvent(event: currentEvent, data: data)
                currentEvent = nil
                dataBuffer.removeAll()
                if data == "[DONE]" { return nil }
                return event
            }
            currentEvent = nil
            return nil
        }

        // Comment line
        if trimmed.hasPrefix(":") {
            return nil
        }

        // Event line
        if trimmed.hasPrefix("event:") {
            let value = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)

            // If we already have buffered data, dispatch it before starting the new event.
            // Some providers (e.g. Azure) don't send empty lines between SSE events.
            if !dataBuffer.isEmpty {
                let data = dataBuffer.joined(separator: "\n")
                let event = SSEEvent(event: currentEvent, data: data)
                currentEvent = value
                dataBuffer.removeAll()
                if data == "[DONE]" { return nil }
                return event
            }

            currentEvent = value
            return nil
        }

        // Data line
        if trimmed.hasPrefix("data:") {
            let value = trimmed.dropFirst(5).trimmingCharacters(in: .init(charactersIn: " "))
            if value == "[DONE]" {
                dataBuffer.removeAll()
                currentEvent = nil
                return nil
            }
            dataBuffer.append(value)
            return nil
        }

        return nil
    }

    /// Flush any remaining buffered event
    public mutating func flush() -> SSEEvent? {
        guard !dataBuffer.isEmpty else { return nil }
        let data = dataBuffer.joined(separator: "\n")
        let event = SSEEvent(event: currentEvent, data: data)
        currentEvent = nil
        dataBuffer.removeAll()
        if data == "[DONE]" { return nil }
        return event
    }
}
