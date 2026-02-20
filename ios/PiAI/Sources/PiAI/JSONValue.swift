import Foundation

/// A Codable wrapper for arbitrary JSON values.
public enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode JSONValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            if value == value.rounded() && value >= Double(Int64.min) && value <= Double(Int64.max) {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Subscript Access

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let arr) = self, index >= 0, index < arr.count else { return nil }
        return arr[index]
    }
}

// MARK: - Convenience Accessors

public extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Conversion Helpers

public extension JSONValue {
    /// Convert JSONValue to Foundation types (String, Double, Bool, NSNull, [Any], [String: Any])
    var toAny: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        case .array(let v): return v.map { $0.toAny }
        case .object(let v): return v.mapValues { $0.toAny }
        }
    }

    /// Create JSONValue from Foundation types
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(n) {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let b as Bool:
            return .bool(b)
        case let arr as [Any]:
            return .array(arr.map { from($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { from($0) })
        case is NSNull:
            return .null
        default:
            return .string(String(describing: value))
        }
    }

    /// Serialize to JSON Data
    func toData(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = .prettyPrinted
        }
        return try encoder.encode(self)
    }

    /// Deserialize from JSON Data
    static func fromData(_ data: Data) throws -> JSONValue {
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Serialize to JSON String
    func toJSONString(prettyPrinted: Bool = false) throws -> String {
        let data = try toData(prettyPrinted: prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - ExpressibleBy Literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}
