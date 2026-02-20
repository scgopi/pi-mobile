import XCTest
@testable import PiTools
import PiAgentCore
import PiAI

final class ReadFileToolTests: XCTestCase {
    var sandboxURL: URL!
    var tool: ReadFileTool!

    override func setUpWithError() throws {
        sandboxURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadFileToolTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        tool = ReadFileTool(sandboxURL: sandboxURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandboxURL)
    }

    // MARK: - Helpers

    private func writeTestFile(_ name: String, content: String) throws {
        let fileURL = sandboxURL.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Read Whole File

    func testReadWholeFileReturnsContentWithLineNumbers() async throws {
        try writeTestFile("test.txt", content: "line one\nline two\nline three")

        let input: JSONValue = .object(["path": .string("test.txt")])
        let result = try await tool.execute(input: input)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.output.contains("1\tline one"))
        XCTAssertTrue(result.output.contains("2\tline two"))
        XCTAssertTrue(result.output.contains("3\tline three"))
    }

    // MARK: - Read With Line Range

    func testReadWithStartAndEndLine() async throws {
        try writeTestFile("lines.txt", content: "a\nb\nc\nd\ne")

        let input: JSONValue = .object([
            "path": .string("lines.txt"),
            "start_line": .number(2),
            "end_line": .number(4),
        ])
        let result = try await tool.execute(input: input)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.output.contains("2\tb"))
        XCTAssertTrue(result.output.contains("3\tc"))
        XCTAssertTrue(result.output.contains("4\td"))
        XCTAssertFalse(result.output.contains("1\ta"))
        XCTAssertFalse(result.output.contains("5\te"))
    }

    // MARK: - Path Traversal

    func testPathTraversalReturnsError() async throws {
        let input: JSONValue = .object(["path": .string("../etc/passwd")])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("outside sandbox") || result.output.contains("not found") || result.output.contains("Error"))
    }

    // MARK: - File Not Found

    func testFileNotFoundReturnsError() async throws {
        let input: JSONValue = .object(["path": .string("nonexistent.txt")])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("not found"))
    }

    // MARK: - Missing Path Parameter

    func testMissingPathReturnsError() async throws {
        let input: JSONValue = .object([:])
        let result = try await tool.execute(input: input)

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.output.contains("path"))
    }

    // MARK: - File Info Header

    func testOutputIncludesFileInfo() async throws {
        try writeTestFile("info.swift", content: "import Foundation")

        let input: JSONValue = .object(["path": .string("info.swift")])
        let result = try await tool.execute(input: input)

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.output.contains("info.swift"))
        XCTAssertTrue(result.output.contains("swift"))
    }

    // MARK: - Tool Metadata

    func testToolNameAndDescription() {
        XCTAssertEqual(tool.name, "read_file")
        XCTAssertFalse(tool.description.isEmpty)
    }
}
