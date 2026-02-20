import XCTest
@testable import PiAI

final class TypesTests: XCTestCase {

    // MARK: - ContentBlock Codable

    func testTextContentBlockRoundTrip() throws {
        let block = ContentBlock.text("hi")
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        if case .text(let text) = decoded {
            XCTAssertEqual(text, "hi")
        } else {
            XCTFail("Expected .text, got \(decoded)")
        }
    }

    func testImageContentBlockRoundTrip() throws {
        let block = ContentBlock.image(base64: "abc123", mimeType: "image/png")
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ContentBlock.self, from: data)
        if case .image(let base64, let mimeType) = decoded {
            XCTAssertEqual(base64, "abc123")
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected .image, got \(decoded)")
        }
    }

    func testContentBlockDecodingUnknownTypeThrows() {
        let json = "{\"type\":\"video\",\"url\":\"http://example.com\"}"
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ContentBlock.self, from: data))
    }

    // MARK: - WireProtocol

    func testWireProtocolRawValues() {
        XCTAssertEqual(WireProtocol.openaiCompletions.rawValue, "openai-completions")
        XCTAssertEqual(WireProtocol.openaiResponses.rawValue, "openai-responses")
        XCTAssertEqual(WireProtocol.anthropic.rawValue, "anthropic")
        XCTAssertEqual(WireProtocol.google.rawValue, "google")
        XCTAssertEqual(WireProtocol.azure.rawValue, "azure")
    }

    func testWireProtocolCodable() throws {
        let original = WireProtocol.openaiCompletions
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WireProtocol.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testWireProtocolAllCases() {
        XCTAssertEqual(WireProtocol.allCases.count, 5)
    }

    // MARK: - ToolCall.input

    func testToolCallInputParsesJSON() {
        let call = ToolCall(id: "1", name: "test", arguments: "{\"key\":\"value\"}")
        let input = call.input
        XCTAssertEqual(input["key"], .string("value"))
    }

    func testToolCallInputInvalidJSONReturnsEmptyObject() {
        let call = ToolCall(id: "1", name: "test", arguments: "not json")
        let input = call.input
        XCTAssertEqual(input, .object([:]))
    }

    func testToolCallInputEmptyStringReturnsEmptyObject() {
        let call = ToolCall(id: "1", name: "test", arguments: "")
        let input = call.input
        XCTAssertEqual(input, .object([:]))
    }

    // MARK: - ToolCall Codable

    func testToolCallCodableRoundTrip() throws {
        let original = ToolCall(id: "tc-1", name: "read_file", arguments: "{\"path\":\"test.txt\"}")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.arguments, original.arguments)
    }

    // MARK: - ToolResult Codable

    func testToolResultCodableRoundTrip() throws {
        let original = ToolResult(toolCallId: "tc-1", output: "success", isError: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolResult.self, from: data)
        XCTAssertEqual(decoded.toolCallId, original.toolCallId)
        XCTAssertEqual(decoded.output, original.output)
        XCTAssertEqual(decoded.isError, original.isError)
    }

    // MARK: - Role

    func testRoleRawValues() {
        XCTAssertEqual(Role.user.rawValue, "user")
        XCTAssertEqual(Role.assistant.rawValue, "assistant")
        XCTAssertEqual(Role.system.rawValue, "system")
    }

    // MARK: - MessageContent

    func testMessageContentTextValue() {
        let textContent = MessageContent.text("hello")
        XCTAssertEqual(textContent.textValue, "hello")

        let blocksContent = MessageContent.blocks([.text("a"), .text("b")])
        XCTAssertEqual(blocksContent.textValue, "ab")
    }

    func testMessageContentBlocksWithImageSkipsImage() {
        let content = MessageContent.blocks([
            .text("text"),
            .image(base64: "abc", mimeType: "image/png"),
            .text("more"),
        ])
        XCTAssertEqual(content.textValue, "textmore")
    }

    // MARK: - ModelCapabilities

    func testModelCapabilitiesDefaults() {
        let caps = ModelCapabilities()
        XCTAssertFalse(caps.vision)
        XCTAssertFalse(caps.toolUse)
        XCTAssertTrue(caps.streaming)
        XCTAssertFalse(caps.reasoning)
    }

    // MARK: - LlmError

    func testLlmErrorDescriptions() {
        let httpError = LlmError.httpError(statusCode: 429, body: "rate limited")
        XCTAssertTrue(httpError.localizedDescription.contains("429"))

        let parseError = LlmError.parseError("bad json")
        XCTAssertTrue(parseError.localizedDescription.contains("bad json"))

        let invalidReq = LlmError.invalidRequest("missing key")
        XCTAssertTrue(invalidReq.localizedDescription.contains("missing key"))
    }
}
