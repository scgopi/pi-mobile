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

    func testMultipleDataLinesConcatenated() {
        var parser = SSELineParser()
        _ = parser.feedLine("data: line1")
        _ = parser.feedLine("data: line2")
        let event = parser.feedLine("")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.data, "line1\nline2")
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
}
