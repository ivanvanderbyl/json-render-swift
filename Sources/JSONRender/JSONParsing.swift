import Foundation

/// A syntax error from ``JSONValue/init(parsing:)``, like the `SyntaxError`
/// thrown by `JSON.parse`.
public struct JSONParseError: Error, Sendable, Equatable {
    public var message: String
    /// The UTF-16 offset where parsing failed.
    public var offset: Int
}

extension JSONValue {
    /// Parses JSON text with `JSON.parse` semantics: strict JSON grammar,
    /// numbers as doubles, and a repeated key keeping its first position with
    /// its last value.
    ///
    /// A lone surrogate escape such as `"\ud800"` becomes U+FFFD because Swift
    /// strings cannot hold unpaired surrogates.
    public init(parsing text: String) throws {
        var parser = JSONParser(units: Array(text.utf16))
        self = try parser.parseDocument()
    }

    /// Parses UTF-8 JSON data with `JSON.parse` semantics.
    public init(parsing data: Data) throws {
        try self.init(parsing: String(decoding: data, as: UTF8.self))
    }

    /// Encodes the value with `JSON.stringify` semantics. Returns `nil` for
    /// `undefined`, which `JSON.stringify` does not encode.
    public func stringified() -> String? {
        if isUndefined { return nil }
        var output = ""
        write(to: &output)
        return output
    }

    private func write(to output: inout String) {
        switch self {
        case .undefined, .null:
            output += "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case let .number(value):
            output += value.isFinite ? JavaScript.numberToString(value) : "null"
        case let .string(value):
            JavaScript.quoteJSONString(value, into: &output)
        case let .array(array):
            output += "["
            for (index, element) in array.enumerated() {
                if index > 0 { output += "," }
                element.write(to: &output)
            }
            output += "]"
        case let .object(object):
            output += "{"
            var first = true
            for (key, member) in object where !member.isUndefined {
                if !first { output += "," }
                first = false
                JavaScript.quoteJSONString(key, into: &output)
                output += ":"
                member.write(to: &output)
            }
            output += "}"
        }
    }
}

private struct JSONParser {
    let units: [UInt16]
    var position = 0

    init(units: [UInt16]) { self.units = units }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        if position < units.count { throw error("Unexpected non-whitespace character after JSON") }
        return value
    }

    private func error(_ message: String) -> JSONParseError {
        JSONParseError(message: message, offset: position)
    }

    private mutating func skipWhitespace() {
        while position < units.count {
            switch units[position] {
            case 0x20, 0x09, 0x0A, 0x0D: position += 1
            default: return
            }
        }
    }

    private mutating func parseValue() throws -> JSONValue {
        guard position < units.count else { throw error("Unexpected end of JSON input") }
        switch units[position] {
        case 0x7B: return try parseObject()
        case 0x5B: return try parseArray()
        case 0x22: return .string(try parseString())
        case 0x74: try expectLiteral("true"); return .bool(true)
        case 0x66: try expectLiteral("false"); return .bool(false)
        case 0x6E: try expectLiteral("null"); return .null
        case 0x2D, 0x30...0x39: return .number(try parseNumber())
        default: throw error("Unexpected token")
        }
    }

    private mutating func expectLiteral(_ literal: String) throws {
        for unit in literal.utf16 {
            guard position < units.count, units[position] == unit else { throw error("Unexpected token") }
            position += 1
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        position += 1
        var object = JSONObject()
        skipWhitespace()
        if position < units.count, units[position] == 0x7D {
            position += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            guard position < units.count, units[position] == 0x22 else { throw error("Expected property name") }
            let key = try parseString()
            skipWhitespace()
            guard position < units.count, units[position] == 0x3A else { throw error("Expected ':' after property name") }
            position += 1
            skipWhitespace()
            object[key] = try parseValue()
            skipWhitespace()
            guard position < units.count else { throw error("Unexpected end of JSON input") }
            if units[position] == 0x2C {
                position += 1
                continue
            }
            if units[position] == 0x7D {
                position += 1
                return .object(object)
            }
            throw error("Expected ',' or '}' after property value")
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        position += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if position < units.count, units[position] == 0x5D {
            position += 1
            return .array(JSONArray(elements))
        }
        while true {
            skipWhitespace()
            elements.append(try parseValue())
            skipWhitespace()
            guard position < units.count else { throw error("Unexpected end of JSON input") }
            if units[position] == 0x2C {
                position += 1
                continue
            }
            if units[position] == 0x5D {
                position += 1
                return .array(JSONArray(elements))
            }
            throw error("Expected ',' or ']' after array element")
        }
    }

    private mutating func parseString() throws -> String {
        position += 1
        var buffer: [UInt16] = []
        while true {
            guard position < units.count else { throw error("Unterminated string in JSON") }
            let unit = units[position]
            position += 1
            switch unit {
            case 0x22:
                return String(decoding: buffer, as: UTF16.self)
            case 0x5C:
                guard position < units.count else { throw error("Unterminated string in JSON") }
                let escape = units[position]
                position += 1
                switch escape {
                case 0x22, 0x5C, 0x2F: buffer.append(escape)
                case 0x62: buffer.append(0x08)
                case 0x66: buffer.append(0x0C)
                case 0x6E: buffer.append(0x0A)
                case 0x72: buffer.append(0x0D)
                case 0x74: buffer.append(0x09)
                case 0x75: buffer.append(try parseHexQuad())
                default: throw error("Bad escaped character in JSON")
                }
            case 0x00..<0x20:
                throw error("Bad control character in string literal in JSON")
            default:
                buffer.append(unit)
            }
        }
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        guard position + 4 <= units.count else { throw error("Bad Unicode escape in JSON") }
        var value: UInt16 = 0
        for _ in 0..<4 {
            let unit = units[position]
            let digit: UInt16
            switch unit {
            case 0x30...0x39: digit = unit - 0x30
            case 0x41...0x46: digit = unit - 0x41 + 10
            case 0x61...0x66: digit = unit - 0x61 + 10
            default: throw error("Bad Unicode escape in JSON")
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    private mutating func parseNumber() throws -> Double {
        let start = position
        if units[position] == 0x2D { position += 1 }
        guard position < units.count else { throw error("No number after minus sign in JSON") }
        if units[position] == 0x30 {
            position += 1
        } else if isDigit(units[position]) {
            while position < units.count, isDigit(units[position]) { position += 1 }
        } else {
            throw error("No number after minus sign in JSON")
        }
        if position < units.count, units[position] == 0x2E {
            position += 1
            guard position < units.count, isDigit(units[position]) else { throw error("Unterminated fractional number in JSON") }
            while position < units.count, isDigit(units[position]) { position += 1 }
        }
        if position < units.count, units[position] == 0x65 || units[position] == 0x45 {
            position += 1
            if position < units.count, units[position] == 0x2B || units[position] == 0x2D { position += 1 }
            guard position < units.count, isDigit(units[position]) else { throw error("Exponent part is missing a number in JSON") }
            while position < units.count, isDigit(units[position]) { position += 1 }
        }
        let literal = String(decoding: units[start..<position], as: UTF16.self)
        return Double(literal) ?? .nan
    }

    private func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }
}
