import XCTest
@testable import PiExtensions
import PiAgentCore
import PiAI

// MARK: - Mock Extension

final class MockExtension: PiExtension {
    let id: String
    let name: String
    let description: String
    var tools: [any Tool] { mockTools }
    var mockTools: [any Tool] = []
    var loadCalled = false
    var unloadCalled = false

    init(id: String, name: String = "Mock", description: String = "Test extension") {
        self.id = id
        self.name = name
        self.description = description
    }

    func onLoad() async {
        loadCalled = true
    }

    func onUnload() async {
        unloadCalled = true
    }

    func beforeToolCall(name: String, input: JSONValue) async -> ToolCallDecision {
        return .allow
    }

    func afterToolCall(name: String, result: AgentToolResult) async {}

    func beforeLlmCall(context: Context) async -> Context {
        return context
    }

    func afterLlmResponse(content: String) async {}
}

// MARK: - Mock Tool

struct MockTool: Tool {
    let name: String
    let description: String
    var parametersSchema: JSONValue { .object([:]) }

    func execute(input: JSONValue) async throws -> AgentToolResult {
        AgentToolResult(output: "mock output")
    }
}

// MARK: - Tests

final class ExtensionRegistryTests: XCTestCase {
    var registry: ExtensionRegistry!

    override func setUp() {
        registry = ExtensionRegistry()
    }

    override func tearDown() {
        registry = nil
    }

    // MARK: - Register & Get

    func testRegisterAndGetExtension() async {
        let ext = MockExtension(id: "ext-1", name: "Test Ext")
        await registry.register(ext)

        let fetched = registry.get(id: "ext-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, "ext-1")
        XCTAssertEqual(fetched?.name, "Test Ext")
    }

    func testGetNonexistentReturnsNil() {
        let fetched = registry.get(id: "nonexistent")
        XCTAssertNil(fetched)
    }

    // MARK: - Unregister

    func testUnregisterRemovesExtension() async {
        let ext = MockExtension(id: "ext-1")
        await registry.register(ext)
        await registry.unregister(id: "ext-1")

        let fetched = registry.get(id: "ext-1")
        XCTAssertNil(fetched)
    }

    func testUnregisterNonexistentDoesNotCrash() async {
        await registry.unregister(id: "nonexistent")
        // Should not throw or crash
    }

    // MARK: - allTools

    func testAllToolsAggregatesFromAllExtensions() async {
        let ext1 = MockExtension(id: "ext-1")
        ext1.mockTools = [MockTool(name: "tool_a", description: "A")]

        let ext2 = MockExtension(id: "ext-2")
        ext2.mockTools = [MockTool(name: "tool_b", description: "B"), MockTool(name: "tool_c", description: "C")]

        await registry.register(ext1)
        await registry.register(ext2)

        let tools = registry.allTools()
        let names = Set(tools.map(\.name))
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(names.contains("tool_a"))
        XCTAssertTrue(names.contains("tool_b"))
        XCTAssertTrue(names.contains("tool_c"))
    }

    func testAllToolsEmptyWhenNoExtensions() {
        let tools = registry.allTools()
        XCTAssertTrue(tools.isEmpty)
    }

    // MARK: - Lifecycle Hooks

    func testOnLoadCalledOnRegister() async {
        let ext = MockExtension(id: "ext-1")
        XCTAssertFalse(ext.loadCalled)

        await registry.register(ext)
        XCTAssertTrue(ext.loadCalled)
    }

    func testOnUnloadCalledOnUnregister() async {
        let ext = MockExtension(id: "ext-1")
        await registry.register(ext)
        XCTAssertFalse(ext.unloadCalled)

        await registry.unregister(id: "ext-1")
        XCTAssertTrue(ext.unloadCalled)
    }

    // MARK: - allExtensions

    func testAllExtensionsReturnsList() async {
        let ext1 = MockExtension(id: "ext-1")
        let ext2 = MockExtension(id: "ext-2")
        await registry.register(ext1)
        await registry.register(ext2)

        let all = registry.allExtensions()
        XCTAssertEqual(all.count, 2)
        let ids = Set(all.map(\.id))
        XCTAssertTrue(ids.contains("ext-1"))
        XCTAssertTrue(ids.contains("ext-2"))
    }

    // MARK: - Register overwrites existing

    func testRegisterOverwritesExisting() async {
        let ext1 = MockExtension(id: "ext-1", name: "First")
        let ext2 = MockExtension(id: "ext-1", name: "Second")
        await registry.register(ext1)
        await registry.register(ext2)

        let fetched = registry.get(id: "ext-1")
        XCTAssertEqual(fetched?.name, "Second")
    }
}
