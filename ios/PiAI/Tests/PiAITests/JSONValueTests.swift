import XCTest
@testable import PiAI

final class JSONValueTests: XCTestCase {

    // MARK: - Codable Round-Trips

    func testStringRoundTrip() throws {
        let original: JSONValue = .string("hello")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNumberRoundTrip() throws {
        let original: JSONValue = .number(42.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testIntegerNumberRoundTrip() throws {
        // Integers encode as Int64 and decode back
        let original: JSONValue = .number(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testBoolRoundTrip() throws {
        let original: JSONValue = .bool(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNullRoundTrip() throws {
        let original: JSONValue = .null
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testArrayRoundTrip() throws {
        let original: JSONValue = .array([.string("a"), .number(1), .bool(false)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testObjectRoundTrip() throws {
        let original: JSONValue = .object(["name": .string("test"), "count": .number(3)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Subscript Access

    func testObjectSubscript() {
        let value: JSONValue = .object(["key": .string("value")])
        XCTAssertEqual(value["key"], .string("value"))
        XCTAssertNil(value["missing"])
    }

    func testArraySubscript() {
        let value: JSONValue = .array([.string("first"), .string("second")])
        XCTAssertEqual(value[0], .string("first"))
        XCTAssertEqual(value[1], .string("second"))
        XCTAssertNil(value[5])
    }

    func testSubscriptOnWrongTypeReturnsNil() {
        let value: JSONValue = .string("not an object")
        XCTAssertNil(value["key"])
        XCTAssertNil(value[0])
    }

    func testArraySubscriptNegativeIndexReturnsNil() {
        let value: JSONValue = .array([.string("a")])
        XCTAssertNil(value[-1])
    }

    // MARK: - Literal Conformances

    func testStringLiteral() {
        let value: JSONValue = "hello"
        XCTAssertEqual(value, .string("hello"))
    }

    func testIntegerLiteral() {
        let value: JSONValue = 42
        XCTAssertEqual(value, .number(42))
    }

    func testFloatLiteral() {
        let value: JSONValue = 3.14
        XCTAssertEqual(value, .number(3.14))
    }

    func testBoolLiteral() {
        let value: JSONValue = true
        XCTAssertEqual(value, .bool(true))
    }

    func testArrayLiteral() {
        let value: JSONValue = ["a", "b"]
        XCTAssertEqual(value, .array([.string("a"), .string("b")]))
    }

    func testDictionaryLiteral() {
        let value: JSONValue = ["key": "val"]
        XCTAssertEqual(value, .object(["key": .string("val")]))
    }

    func testNilLiteral() {
        let value: JSONValue = nil
        XCTAssertEqual(value, .null)
    }

    // MARK: - Convenience Accessors

    func testStringValue() {
        XCTAssertEqual(JSONValue.string("test").stringValue, "test")
        XCTAssertNil(JSONValue.number(1).stringValue)
    }

    func testNumberValue() {
        XCTAssertEqual(JSONValue.number(3.14).numberValue, 3.14)
        XCTAssertNil(JSONValue.string("nope").numberValue)
    }

    func testIntValue() {
        XCTAssertEqual(JSONValue.number(5).intValue, 5)
        XCTAssertNil(JSONValue.bool(true).intValue)
    }

    func testBoolValue() {
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertNil(JSONValue.number(1).boolValue)
    }

    func testArrayValue() {
        let arr: [JSONValue] = [.number(1)]
        XCTAssertEqual(JSONValue.array(arr).arrayValue, arr)
        XCTAssertNil(JSONValue.string("nope").arrayValue)
    }

    func testObjectValue() {
        let obj: [String: JSONValue] = ["k": .string("v")]
        XCTAssertEqual(JSONValue.object(obj).objectValue, obj)
        XCTAssertNil(JSONValue.null.objectValue)
    }

    func testIsNull() {
        XCTAssertTrue(JSONValue.null.isNull)
        XCTAssertFalse(JSONValue.string("").isNull)
    }

    // MARK: - toJSONString and fromData

    func testToJSONString() throws {
        let value: JSONValue = .object(["name": .string("test")])
        let jsonString = try value.toJSONString()
        XCTAssertTrue(jsonString.contains("\"name\""))
        XCTAssertTrue(jsonString.contains("\"test\""))
    }

    func testFromData() throws {
        let json = "{\"a\":1}"
        let data = json.data(using: .utf8)!
        let value = try JSONValue.fromData(data)
        XCTAssertEqual(value["a"], .number(1))
    }

    func testToDataAndFromDataRoundTrip() throws {
        let original: JSONValue = .object([
            "str": .string("hello"),
            "num": .number(42),
            "arr": .array([.bool(true), .null]),
        ])
        let data = try original.toData()
        let decoded = try JSONValue.fromData(data)
        XCTAssertEqual(decoded, original)
    }
}
