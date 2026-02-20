import XCTest
@testable import PiTools
import PiAgentCore
import PiAI

final class EditFileToolTests: XCTestCase {
    var sandboxURL: URL!
    var tool: EditFileTool!

    override func setUpWithError() throws {
        sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditFileToolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        tool = EditFileTool(sandboxURL: sandboxURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandboxURL)
    }

    // MARK: - Helpers

    private func writeTestFile(_ name: String, content: String) throws {
        let fileURL = sandboxURL.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func readTestFile(_ name: String) throws -> String {
        let fileURL = sandboxURL.appendingPathComponent(name)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    // MARK: - Successful Replace

    func testSearchReplaceWorks() async throws {
        try writeTestFile("test.txt", content: "Hello world, this is a test.")

        let input: JSONValue = .object([
            "path": .string("test.txt"),
            "old_string": .string("world"),
            "new_string": .string("Swift"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.output.contains("replaced 1 occurrence"))

        let content = try readTestFile("test.txt")
        XCTAssertEqual(content, "Hello Swift, this is a test.")
    }

    // MARK: - old_string Not Found

    func testOldStringNotFoundReturnsError() async throws {
        try writeTestFile("test.txt", content: "Hello world")

        let input: JSONValue = .object([
            "path": .string("test.txt"),
            "old_string": .string("missing"),
            "new_string": .string("replacement"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("not found"))
    }

    // MARK: - old_string Multiple Matches

    func testOldStringMultipleMatchesReturnsError() async throws {
        try writeTestFile("test.txt", content: "foo bar foo baz foo")

        let input: JSONValue = .object([
            "path": .string("test.txt"),
            "old_string": .string("foo"),
            "new_string": .string("qux"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("3 times") || result.output.contains("exactly once"))
    }

    // MARK: - File Not Found

    func testFileNotFoundReturnsError() async throws {
        let input: JSONValue = .object([
            "path": .string("nonexistent.txt"),
            "old_string": .string("a"),
            "new_string": .string("b"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("not found"))
    }

    // MARK: - Path Traversal

    func testPathTraversalReturnsError() async throws {
        let input: JSONValue = .object([
            "path": .string("../../etc/passwd"),
            "old_string": .string("root"),
            "new_string": .string("hacked"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
    }

    // MARK: - Missing Parameters

    func testMissingPathReturnsError() async throws {
        let input: JSONValue = .object([
            "old_string": .string("a"),
            "new_string": .string("b"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("path"))
    }

    func testMissingOldStringReturnsError() async throws {
        let input: JSONValue = .object([
            "path": .string("test.txt"),
            "new_string": .string("b"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("old_string"))
    }

    func testMissingNewStringReturnsError() async throws {
        let input: JSONValue = .object([
            "path": .string("test.txt"),
            "old_string": .string("a"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("new_string"))
    }

    // MARK: - Multiline Replace

    func testMultilineReplace() async throws {
        try writeTestFile("multi.txt", content: "line1\nline2\nline3\nline4")

        let input: JSONValue = .object([
            "path": .string("multi.txt"),
            "old_string": .string("line2\nline3"),
            "new_string": .string("replaced2\nreplaced3"),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertFalse(result.isError)
        let content = try readTestFile("multi.txt")
        XCTAssertEqual(content, "line1\nreplaced2\nreplaced3\nline4")
    }

    // MARK: - Tool Metadata

    func testToolNameAndDescription() {
        XCTAssertEqual(tool.name, "edit_file")
        XCTAssertFalse(tool.description.isEmpty)
    }
}
