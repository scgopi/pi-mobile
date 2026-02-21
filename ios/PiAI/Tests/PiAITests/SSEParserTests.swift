import XCTest
@testable import PiAI

final class SSEParserTests: XCTestCase {

    // MARK: - SSEParser.parse()

    func testParseDataLine() {
        let event = SSEParser.parse(line: "data: {\"content\":\"hello\"}")
        XCTAssertNotNil(event)
        XCTAssertNil(event?.event)
        XCTAssertEqual(event?.data, "{\"content\":\"hello\"}")
    }

    func testParseDataLineWithoutSpace() {
        let event = SSEParser.parse(line: "data:{\"content\":\"hello\"}")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "{\"content\":\"hello\"}")
    }

    func testParseDoneReturnsNil() {
        let event = SSEParser.parse(line: "data: [DONE]")
        XCTAssertNil(event)
    }

    func testParseDoneWithoutSpaceReturnsNil() {
        let event = SSEParser.parse(line: "data:[DONE]")
        XCTAssertNil(event)
    }

    func testParseCommentReturnsNil() {
        let event = SSEParser.parse(line: ": keep-alive")
        XCTAssertNil(event)
    }

    func testParseEmptyLineReturnsNil() {
        let event = SSEParser.parse(line: "")
        XCTAssertNil(event)
    }

    func testParseWhitespaceOnlyReturnsNil() {
        let event = SSEParser.parse(line: "   ")
        XCTAssertNil(event)
    }

    func testParseEventLine() {
        let event = SSEParser.parse(line: "event: message")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "message")
        XCTAssertEqual(event?.data, "")
    }

    func testParseEventLineWithoutSpace() {
        let event = SSEParser.parse(line: "event:message")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "message")
    }

    func testParseUnknownFieldReturnsNil() {
        let event = SSEParser.parse(line: "id: 12345")
        XCTAssertNil(event)
    }

    // MARK: - SSELineParser

    func testFeedLineDataThenEmptyDispatches() {
        var parser = SSELineParser()
        let result1 = parser.feedLine("data: hello")
        XCTAssertNil(result1, "Data line alone should not dispatch")

        let result2 = parser.feedLine("")
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.data, "hello")
        XCTAssertNil(result2?.event)
    }

    func testConsecutiveDataLinesDispatchEagerly() {
        // AsyncLineSequence skips empty lines, so consecutive data: lines
        // trigger eager dispatch of the previous buffered data.
        var parser = SSELineParser()
        let result1 = parser.feedLine("data: line1")
        XCTAssertNil(result1, "First data line should buffer")

        let result2 = parser.feedLine("data: line2")
        XCTAssertNotNil(result2, "Second data line should dispatch first")
        XCTAssertEqual(result2?.data, "line1")

        // line2 remains buffered
        let flushed = parser.flush()
        XCTAssertNotNil(flushed)
        XCTAssertEqual(flushed?.data, "line2")
    }

    func testEventLineBeforeData() {
        var parser = SSELineParser()
        _ = parser.feedLine("event: custom")
        _ = parser.feedLine("data: payload")
        let event = parser.feedLine("")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "custom")
        XCTAssertEqual(event?.data, "payload")
    }

    func testFlushReturnsBufferedData() {
        var parser = SSELineParser()
        _ = parser.feedLine("data: buffered")
        let event = parser.flush()
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "buffered")
    }

    func testFlushEmptyReturnsNil() {
        var parser = SSELineParser()
        let event = parser.flush()
        XCTAssertNil(event)
    }

    func testDoneInFeedLineClearsBuffer() {
        var parser = SSELineParser()
        let result = parser.feedLine("data: [DONE]")
        XCTAssertNil(result)

        // Buffer should be cleared
        let flushed = parser.flush()
        XCTAssertNil(flushed)
    }

    func testDoneDispatchedViaEmptyLineReturnsNil() {
        var parser = SSELineParser()
        _ = parser.feedLine("data: [DONE]")
        let event = parser.feedLine("")
        XCTAssertNil(event, "[DONE] data dispatched via empty line should return nil")
    }

    func testCommentLineIgnored() {
        var parser = SSELineParser()
        let result = parser.feedLine(": this is a comment")
        XCTAssertNil(result)
    }

    func testFlushWithEventName() {
        var parser = SSELineParser()
        _ = parser.feedLine("event: ping")
        _ = parser.feedLine("data: pong")
        let event = parser.flush()
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "ping")
        XCTAssertEqual(event?.data, "pong")
    }

    func testNewEventDispatchesPreviousBufferWithoutEmptyLine() {
        var parser = SSELineParser()
        _ = parser.feedLine("event: first")
        _ = parser.feedLine("data: data1")
        // A new event line dispatches the previous buffered event
        let dispatched = parser.feedLine("event: second")
        XCTAssertNotNil(dispatched)
        XCTAssertEqual(dispatched?.event, "first")
        XCTAssertEqual(dispatched?.data, "data1")
    }

    // MARK: - AsyncLineSequence simulation (no empty lines)

    func testNoEmptyLinesOpenAIStream() {
        // Simulates AsyncLineSequence which skips empty lines.
        // A typical OpenAI SSE stream without empty line delimiters:
        //   data: {"choices":[{"delta":{"content":"Hello"}}]}
        //   data: {"choices":[{"delta":{"content":" world"}}]}
        //   data: [DONE]
        var parser = SSELineParser()
        let events = feedAllNoEmpty(parser: &parser, lines: [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
            "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}",
            "data: [DONE]",
        ])
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].data.contains("Hello"))
        XCTAssertTrue(events[1].data.contains("world"))
    }

    func testNoEmptyLinesWithEventPrefix() {
        // Azure-style events with event: prefix, no empty lines
        var parser = SSELineParser()
        let events = feedAllNoEmpty(parser: &parser, lines: [
            "event: message",
            "data: {\"id\":\"1\"}",
            "event: message",
            "data: {\"id\":\"2\"}",
        ])
        // First event dispatched when second event: arrives
        // Second event dispatched via flush
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].data.contains("\"1\""))
        XCTAssertTrue(events[1].data.contains("\"2\""))
    }

    func testNewDataLineResetsCurrentEvent() {
        // Verify currentEvent is reset after eager dispatch
        var parser = SSELineParser()
        _ = parser.feedLine("event: custom")
        _ = parser.feedLine("data: first")
        let dispatched = parser.feedLine("data: second")
        XCTAssertNotNil(dispatched)
        XCTAssertEqual(dispatched?.event, "custom")
        XCTAssertEqual(dispatched?.data, "first")

        // "second" is now buffered without an event name
        let flushed = parser.flush()
        XCTAssertNotNil(flushed)
        XCTAssertNil(flushed?.event, "currentEvent should have been reset")
        XCTAssertEqual(flushed?.data, "second")
    }

    // MARK: - Helpers

    /// Feed lines without empty-line delimiters (simulating AsyncLineSequence),
    /// then flush, returning all dispatched events.
    private func feedAllNoEmpty(parser: inout SSELineParser, lines: [String]) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for line in lines {
            if let event = parser.feedLine(line) {
                events.append(event)
            }
        }
        if let remaining = parser.flush() {
            events.append(remaining)
        }
        return events
    }
}
