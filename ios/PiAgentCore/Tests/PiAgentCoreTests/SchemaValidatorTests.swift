import XCTest
@testable import PiAgentCore
import PiAI

final class SchemaValidatorTests: XCTestCase {
    let validator = SchemaValidator()

    // MARK: - Valid Object

    func testValidObjectPassesValidation() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("name")]),
            "properties": .object([
                "name": .object(["type": .string("string")]),
            ]),
        ])
        let value: JSONValue = .object(["name": .string("Alice")])
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    // MARK: - Missing Required Field

    func testMissingRequiredFieldFails() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("name"), .string("age")]),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "age": .object(["type": .string("integer")]),
            ]),
        ])
        let value: JSONValue = .object(["name": .string("Alice")])
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.path, "age")
        XCTAssertTrue(result.errors.first?.message.contains("Required") ?? false)
    }

    // MARK: - Wrong Type

    func testWrongTypeFails() {
        let schema: JSONValue = .object([
            "type": .string("string"),
        ])
        let value: JSONValue = .number(42)
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.message.contains("Expected type") ?? false)
    }

    func testCorrectTypePasses() {
        let schema: JSONValue = .object([
            "type": .string("string"),
        ])
        let value: JSONValue = .string("hello")
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Enum Constraint

    func testEnumValidValuePasses() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "enum": .array([.string("red"), .string("green"), .string("blue")]),
        ])
        let value: JSONValue = .string("green")
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    func testEnumInvalidValueFails() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "enum": .array([.string("red"), .string("green"), .string("blue")]),
        ])
        let value: JSONValue = .string("yellow")
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.message.contains("enum") ?? false)
    }

    // MARK: - Nested Object Validation

    func testNestedObjectValidation() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "address": .object([
                    "type": .string("object"),
                    "required": .array([.string("city")]),
                    "properties": .object([
                        "city": .object(["type": .string("string")]),
                    ]),
                ]),
            ]),
        ])
        // Missing required nested field
        let value: JSONValue = .object([
            "address": .object([:]),
        ])
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.path.contains("city") ?? false)
    }

    func testNestedObjectValidPasses() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "address": .object([
                    "type": .string("object"),
                    "required": .array([.string("city")]),
                    "properties": .object([
                        "city": .object(["type": .string("string")]),
                    ]),
                ]),
            ]),
        ])
        let value: JSONValue = .object([
            "address": .object(["city": .string("NYC")]),
        ])
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Array Items Validation

    func testArrayItemsValidation() {
        let schema: JSONValue = .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
        ])
        let value: JSONValue = .array([.string("a"), .string("b")])
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    func testArrayItemsInvalidFails() {
        let schema: JSONValue = .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
        ])
        let value: JSONValue = .array([.string("a"), .number(42)])
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.path.contains("[1]") ?? false)
    }

    // MARK: - Number Min/Max

    func testNumberMinimumPasses() {
        let schema: JSONValue = .object([
            "type": .string("number"),
            "minimum": .number(0),
        ])
        let value: JSONValue = .number(5)
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    func testNumberBelowMinimumFails() {
        let schema: JSONValue = .object([
            "type": .string("number"),
            "minimum": .number(10),
        ])
        let value: JSONValue = .number(5)
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.message.contains("less than minimum") ?? false)
    }

    func testNumberAboveMaximumFails() {
        let schema: JSONValue = .object([
            "type": .string("number"),
            "maximum": .number(100),
        ])
        let value: JSONValue = .number(150)
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.message.contains("greater than maximum") ?? false)
    }

    func testNumberWithinRangePasses() {
        let schema: JSONValue = .object([
            "type": .string("number"),
            "minimum": .number(0),
            "maximum": .number(100),
        ])
        let value: JSONValue = .number(50)
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - String MinLength/MaxLength

    func testStringMinLengthPasses() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "minLength": .number(3),
        ])
        let value: JSONValue = .string("hello")
        let result = validator.validate(value, against: schema)
        XCTAssertTrue(result.isValid)
    }

    func testStringBelowMinLengthFails() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "minLength": .number(5),
        ])
        let value: JSONValue = .string("hi")
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.message.contains("less than minLength") ?? false)
    }

    func testStringAboveMaxLengthFails() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "maxLength": .number(3),
        ])
        let value: JSONValue = .string("toolong")
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.first?.message.contains("greater than maxLength") ?? false)
    }

    // MARK: - Path Reporting

    func testPathReportingOnNestedError() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "config": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["type": .string("number")]),
                    ]),
                ]),
            ]),
        ])
        let value: JSONValue = .object([
            "config": .object(["value": .string("not a number")]),
        ])
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first?.path, "config.value")
    }

    // MARK: - Null required field

    func testNullRequiredFieldFails() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "required": .array([.string("name")]),
            "properties": .object([
                "name": .object(["type": .string("string")]),
            ]),
        ])
        let value: JSONValue = .object(["name": .null])
        let result = validator.validate(value, against: schema)
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Boolean type validation

    func testBooleanTypeValidation() {
        let schema: JSONValue = .object(["type": .string("boolean")])
        XCTAssertTrue(validator.validate(.bool(true), against: schema).isValid)
        XCTAssertFalse(validator.validate(.string("true"), against: schema).isValid)
    }

    // MARK: - ValidationResult.valid

    func testValidResultStatic() {
        let result = ValidationResult.valid
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }
}
