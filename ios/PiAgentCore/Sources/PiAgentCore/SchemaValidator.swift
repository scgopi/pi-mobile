import Foundation
import PiAI

public struct ValidationError: Error, LocalizedError, Sendable {
    public let path: String
    public let message: String

    public var errorDescription: String? {
        return path.isEmpty ? message : "\(path): \(message)"
    }
}

public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [ValidationError]

    public static let valid = ValidationResult(isValid: true, errors: [])

    public static func invalid(_ errors: [ValidationError]) -> ValidationResult {
        return ValidationResult(isValid: false, errors: errors)
    }
}

public struct SchemaValidator: Sendable {
    public init() {}

    /// Validate a JSONValue against a JSON Schema (subset).
    public func validate(_ value: JSONValue, against schema: JSONValue, path: String = "") -> ValidationResult {
        var errors: [ValidationError] = []
        validateValue(value, schema: schema, path: path, errors: &errors)
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    private func validateValue(_ value: JSONValue, schema: JSONValue, path: String, errors: inout [ValidationError]) {
        guard case .object(let schemaObj) = schema else { return }

        // Check type constraint
        if let typeValue = schemaObj["type"]?.stringValue {
            let typeValid: Bool
            switch typeValue {
            case "string":
                typeValid = value.stringValue != nil
            case "number", "integer":
                typeValid = value.numberValue != nil
            case "boolean":
                typeValid = value.boolValue != nil
            case "array":
                typeValid = value.arrayValue != nil
            case "object":
                typeValid = value.objectValue != nil
            case "null":
                typeValid = value.isNull
            default:
                typeValid = true
            }

            if !typeValid {
                errors.append(ValidationError(path: path, message: "Expected type '\(typeValue)'"))
                return
            }
        }

        // Check required fields for objects
        if let requiredFields = schemaObj["required"]?.arrayValue,
           let objValue = value.objectValue {
            for field in requiredFields {
                if let fieldName = field.stringValue {
                    if objValue[fieldName] == nil || objValue[fieldName]?.isNull == true {
                        errors.append(ValidationError(
                            path: path.isEmpty ? fieldName : "\(path).\(fieldName)",
                            message: "Required field missing"
                        ))
                    }
                }
            }
        }

        // Check properties for objects
        if let properties = schemaObj["properties"]?.objectValue,
           let objValue = value.objectValue {
            for (key, propSchema) in properties {
                if let propValue = objValue[key] {
                    let propPath = path.isEmpty ? key : "\(path).\(key)"
                    validateValue(propValue, schema: propSchema, path: propPath, errors: &errors)
                }
            }
        }

        // Check enum constraint
        if let enumValues = schemaObj["enum"]?.arrayValue {
            if !enumValues.contains(value) {
                let allowedStr = enumValues.compactMap { $0.stringValue ?? "\($0)" }.joined(separator: ", ")
                errors.append(ValidationError(path: path, message: "Value not in enum: [\(allowedStr)]"))
            }
        }

        // Check items for arrays
        if let items = schemaObj["items"],
           let arrayValue = value.arrayValue {
            for (index, element) in arrayValue.enumerated() {
                validateValue(element, schema: items, path: "\(path)[\(index)]", errors: &errors)
            }
        }

        // Check minimum/maximum for numbers
        if let numValue = value.numberValue {
            if let minimum = schemaObj["minimum"]?.numberValue, numValue < minimum {
                errors.append(ValidationError(path: path, message: "Value \(numValue) is less than minimum \(minimum)"))
            }
            if let maximum = schemaObj["maximum"]?.numberValue, numValue > maximum {
                errors.append(ValidationError(path: path, message: "Value \(numValue) is greater than maximum \(maximum)"))
            }
        }

        // Check minLength/maxLength for strings
        if let strValue = value.stringValue {
            if let minLength = schemaObj["minLength"]?.intValue, strValue.count < minLength {
                errors.append(ValidationError(path: path, message: "String length \(strValue.count) is less than minLength \(minLength)"))
            }
            if let maxLength = schemaObj["maxLength"]?.intValue, strValue.count > maxLength {
                errors.append(ValidationError(path: path, message: "String length \(strValue.count) is greater than maxLength \(maxLength)"))
            }
        }
    }
}
