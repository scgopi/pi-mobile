import XCTest
@testable import PiAgentCore
import PiAI

// MARK: - Test Tool

/// A simple tool for testing executeTool logic in AgentLoop.
struct EchoTool: Tool {
    let name = "echo"
    let description = "Echoes the input message"

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "required": .array([.string("message")]),
            "properties": .object([
                "message": .object(["type": .string("string")]),
            ]),
        ])
    }

    func execute(input: JSONValue) async throws -> AgentToolResult {
        let msg = input["message"]?.stringValue ?? ""
        return AgentToolResult(output: "Echo: \(msg)")
    }
}

struct FailingTool: Tool {
    let name = "fail"
    let description = "Always throws an error"

    var parametersSchema: JSONValue {
        .object(["type": .string("object")])
    }

    func execute(input: JSONValue) async throws -> AgentToolResult {
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tool execution failed"])
    }
}

// MARK: - Tests

final class AgentLoopTests: XCTestCase {

    // MARK: - Tool Protocol

    func testEchoToolExecutes() async throws {
        let tool = EchoTool()
        let input: JSONValue = .object(["message": .string("hello")])
        let result = try await tool.execute(input: input)
        XCTAssertEqual(result.output, "Echo: hello")
        XCTAssertFalse(result.isError)
    }

    func testEchoToolSchema() {
        let tool = EchoTool()
        XCTAssertEqual(tool.name, "echo")
        XCTAssertNotNil(tool.parametersSchema["properties"])
        XCTAssertNotNil(tool.parametersSchema["required"])
    }

    func testFailingToolThrows() async {
        let tool = FailingTool()
        do {
            _ = try await tool.execute(input: .object([:]))
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("failed"))
        }
    }

    // MARK: - SchemaValidator Integration

    func testSchemaValidatorRejectsInvalidInput() {
        let validator = SchemaValidator()
        let tool = EchoTool()

        // Missing required "message" field
        let input: JSONValue = .object([:])
        let result = validator.validate(input, against: tool.parametersSchema)
        XCTAssertFalse(result.isValid)
    }

    func testSchemaValidatorAcceptsValidInput() {
        let validator = SchemaValidator()
        let tool = EchoTool()

        let input: JSONValue = .object(["message": .string("hello")])
        let result = validator.validate(input, against: tool.parametersSchema)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - AgentToolResult

    func testAgentToolResultDefaults() {
        let result = AgentToolResult(output: "test")
        XCTAssertEqual(result.output, "test")
        XCTAssertFalse(result.isError)
        XCTAssertNil(result.details)
        XCTAssertEqual(result.toolCallId, "")
    }

    func testAgentToolResultWithError() {
        let result = AgentToolResult(
            toolCallId: "tc-1",
            output: "Something went wrong",
            details: .error(message: "bad", code: "ERR"),
            isError: true
        )
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.toolCallId, "tc-1")
    }

    // MARK: - AgentEvent

    func testAgentEventTypes() {
        // Verify we can construct all event types without crashing
        let events: [AgentEvent] = [
            .streamDelta("text"),
            .thinkingDelta("thinking"),
            .assistantMessage(content: "msg", thinking: nil),
            .toolCallStarted(name: "tool", input: .null),
            .toolCallCompleted(name: "tool", result: AgentToolResult(output: "done")),
            .usageUpdate(inputTokens: 100, outputTokens: 50),
            .error("err"),
            .done,
        ]
        XCTAssertEqual(events.count, 8)
    }

    // MARK: - ToolCall

    func testToolCallInputParsing() {
        let call = ToolCall(id: "tc-1", name: "echo", arguments: "{\"message\":\"hello\"}")
        let input = call.input
        XCTAssertEqual(input["message"]?.stringValue, "hello")
    }

    func testToolCallInvalidArgumentsReturnsEmptyObject() {
        let call = ToolCall(id: "tc-1", name: "echo", arguments: "not json")
        XCTAssertEqual(call.input, .object([:]))
    }

    // MARK: - AgentLoop Initialization

    func testAgentLoopCanBeCreated() {
        let client = LlmClient()
        let loop = AgentLoop(llmClient: client)
        // Verify it can be created without crashing
        XCTAssertNotNil(loop)
    }
}
