import Foundation

/// A JSON Schema validator that reaches the same verdicts as zod.
///
/// Catalogs defined in TypeScript describe props with zod. Exported with
/// `z.toJSONSchema(schema, { io: "input" })`, the JSON Schema keeps enough of
/// the zod schema for this validator to accept and reject the same values,
/// produce the same parsed data, and report the same issues in zod's format.
///
/// The keywords zod emits are supported: `type` (including type arrays),
/// `const`, `enum`, `properties`, `required`, `additionalProperties`,
/// `propertyNames`, `items`, `prefixItems`, `minItems`, `maxItems`,
/// `minLength`, `maxLength`, `pattern`, `format`, `minimum`, `maximum`,
/// `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`, `anyOf`, `oneOf`,
/// `allOf`, `not`, `default`, `$ref` and `$defs` / `definitions`. Annotations
/// such as `title` and `description` are ignored.
///
/// The import reads JSON Schema the way zod writes it:
/// - An object without `additionalProperties` strips unknown keys from the
///   parsed data (zod `z.object`); `false` rejects them (`z.strictObject`);
///   `{}` keeps them (`z.looseObject`); a schema validates them (`catchall`).
/// - An object with `propertyNames` is a record.
/// - `anyOf` of one schema and `{ "type": "null" }`, or a two-entry type
///   array with "null", is nullable and reports the inner schema's issues.
/// - `oneOf` whose branches share a `const` property is a discriminated union.
/// - `pattern`, `format` and length checks run in the order they appear, and
///   string lengths count code points, as zod 4.6 does.
public struct JSONSchema: Sendable {
    /// The schema document as given.
    public let document: JSONValue
    let root: SchemaNode
    let definitions: [String: SchemaNode]

    /// Compiles a schema. Throws for a document that is not a schema, or a
    /// `$ref` that does not resolve inside the document.
    public init(_ document: JSONValue) throws {
        self.document = document
        var compiler = SchemaCompiler(document: document)
        root = try compiler.compile(document, at: "#")
        try compiler.resolvePendingReferences()
        definitions = compiler.compiled
    }

    init(root: SchemaNode, document: JSONValue = .undefined) {
        self.document = document
        self.root = root
        definitions = [:]
    }

    /// Validates a value, like zod's `safeParse`.
    public func validate(_ value: JSONValue) -> SchemaResult {
        var issues: [SchemaIssue] = []
        let data = SchemaValidator(definitions: definitions).check(root, value, path: [], issues: &issues)
        return issues.isEmpty
            ? SchemaResult(success: true, data: data, issues: [])
            : SchemaResult(success: false, data: .undefined, issues: issues)
    }
}

/// The outcome of ``JSONSchema/validate(_:)``, like zod's `safeParse` result.
public struct SchemaResult: Sendable, Equatable {
    public var success: Bool
    /// The parsed value: unknown keys stripped from non-strict objects and
    /// defaults filled in. `undefined` when validation fails.
    public var data: JSONValue
    public var issues: [SchemaIssue]
}

/// One problem found by ``JSONSchema``, like a zod issue.
public struct SchemaIssue: Sendable, Equatable, CustomStringConvertible {
    /// The zod issue code, such as "invalid_type" or "too_small".
    public var code: String
    /// Where the problem is: object keys as strings and array indices as numbers.
    public var path: [JSONValue]
    /// zod's English message for the issue.
    public var message: String

    public var description: String {
        let location = path.map(\.javaScriptString).joined(separator: ".")
        return location.isEmpty ? message : "\(location): \(message)"
    }
}

// MARK: - Compiled schema

/// One compiled schema location. Immutable after compilation.
final class SchemaNode: @unchecked Sendable {
    enum Additional {
        /// No `additionalProperties`: accept unknown keys, drop them from data.
        case strip
        /// `additionalProperties: false`.
        case strict
        /// `additionalProperties: true` or `{}`: accept and keep.
        case passthrough
        /// `additionalProperties` with a schema: validate and keep.
        case schema(SchemaNode)
    }

    enum StringCheck {
        case minLength(Int)
        case maxLength(Int)
        case length(Int)
        case pattern(source: String, regex: JavaScriptRegex?, format: String?)
        case url
    }

    var acceptsAnything = false
    var rejectsEverything = false
    var reference: String?
    var embedded: JSONSchema?
    var types: [String]?
    var constValue: JSONValue?
    var enumValues: [JSONValue]?
    var stringChecks: [StringCheck] = []
    var minimum: Double?
    var maximum: Double?
    var exclusiveMinimum: Double?
    var exclusiveMaximum: Double?
    var multipleOf: Double?
    var items: SchemaNode?
    var itemsForbidden = false
    var prefixItems: [SchemaNode]?
    var minItems: Int?
    var maxItems: Int?
    var properties: [(key: String, node: SchemaNode)] = []
    var hasProperties = false
    var required: [String] = []
    var additional: Additional = .strip
    var propertyNames: SchemaNode?
    var anyOf: [SchemaNode]?
    var oneOf: [SchemaNode]?
    var allOf: [SchemaNode]?
    var not: SchemaNode?
    var defaultValue: JSONValue?

    init() {}

    static func anything() -> SchemaNode {
        let node = SchemaNode()
        node.acceptsAnything = true
        return node
    }

    /// A node that validates with another compiled schema, keeping that
    /// schema's own `$defs`.
    static func embedding(_ schema: JSONSchema) -> SchemaNode {
        let node = SchemaNode()
        node.embedded = schema
        return node
    }

    /// True when the schema accepts `undefined`, which zod reports as a
    /// "nonoptional" issue for a missing required key.
    var acceptsUndefined: Bool {
        if acceptsAnything { return true }
        if let embedded { return embedded.root.acceptsUndefined }
        return false
    }
}

/// A JSON Schema document that cannot be compiled.
public enum SchemaDocumentError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidSchema(String)
    case unresolvedReference(String)

    public var description: String {
        switch self {
        case let .invalidSchema(location): "The value at \(location) is not a JSON Schema."
        case let .unresolvedReference(reference): "The schema reference \(reference) does not resolve."
        }
    }
}

private struct SchemaCompiler {
    let document: JSONValue
    var compiled: [String: SchemaNode] = [:]
    var pending: [String] = []

    init(document: JSONValue) { self.document = document }

    mutating func compile(_ schema: JSONValue, at location: String) throws -> SchemaNode {
        switch schema {
        case .bool(true):
            return .anything()
        case .bool(false):
            let node = SchemaNode()
            node.rejectsEverything = true
            return node
        case let .object(object):
            return try compile(object, at: location)
        default:
            throw SchemaDocumentError.invalidSchema(location)
        }
    }

    private static let annotations: Set<String> = [
        "$schema", "$id", "$comment", "$anchor", "$defs", "definitions", "title", "description",
        "examples", "deprecated", "readOnly", "writeOnly", "id", "contentEncoding", "contentMediaType",
    ]

    private mutating func compile(_ object: JSONObject, at location: String) throws -> SchemaNode {
        let node = SchemaNode()
        if object.keys.allSatisfy(Self.annotations.contains) {
            node.acceptsAnything = true
            return node
        }
        if case let .string(reference)? = object["$ref"] {
            node.reference = reference
            pending.append(reference)
            return node
        }
        if let type = object["type"] {
            switch type {
            case let .string(name): node.types = [name]
            case let .array(names): node.types = names.compactMap(\.stringValue)
            default: throw SchemaDocumentError.invalidSchema(location)
            }
        }
        node.constValue = object["const"]
        if case let .array(values)? = object["enum"] { node.enumValues = values.elements }
        if let value = object["default"] { node.defaultValue = value }

        // String checks run in the order their keywords appear.
        let format = object["format"]?.stringValue
        let minLength = object["minLength"]?.numberValue.map { Int($0) }
        let maxLength = object["maxLength"]?.numberValue.map { Int($0) }
        var addedLength = false
        for key in object.keys {
            switch key {
            case "minLength", "maxLength":
                if let minLength, let maxLength, minLength == maxLength {
                    if !addedLength { node.stringChecks.append(.length(minLength)) }
                    addedLength = true
                } else if key == "minLength", let minLength {
                    node.stringChecks.append(.minLength(minLength))
                } else if key == "maxLength", let maxLength {
                    node.stringChecks.append(.maxLength(maxLength))
                }
            case "pattern":
                if case let .string(source)? = object["pattern"] {
                    node.stringChecks.append(.pattern(source: source, regex: JavaScriptRegex(source), format: format))
                }
            case "format":
                if object["pattern"] == nil, format == "uri" || format == "url" {
                    node.stringChecks.append(.url)
                }
            default:
                break
            }
        }

        node.minimum = object["minimum"]?.numberValue
        node.maximum = object["maximum"]?.numberValue
        switch object["exclusiveMinimum"] {
        case let .number(value)?: node.exclusiveMinimum = value
        case .bool(true)?: node.exclusiveMinimum = node.minimum; node.minimum = nil
        default: break
        }
        switch object["exclusiveMaximum"] {
        case let .number(value)?: node.exclusiveMaximum = value
        case .bool(true)?: node.exclusiveMaximum = node.maximum; node.maximum = nil
        default: break
        }
        node.multipleOf = object["multipleOf"]?.numberValue

        if case let .array(prefix)? = object["prefixItems"] {
            node.prefixItems = try prefix.enumerated().map { try compile($0.element, at: "\(location)/prefixItems/\($0.offset)") }
        }
        switch object["items"] {
        case .bool(false)?:
            node.itemsForbidden = true
        case let .array(tuple)?:
            // Draft 7 tuples.
            node.prefixItems = try tuple.enumerated().map { try compile($0.element, at: "\(location)/items/\($0.offset)") }
        case let items?:
            node.items = try compile(items, at: "\(location)/items")
        case nil:
            break
        }
        if node.prefixItems != nil, object["additionalItems"] == false { node.itemsForbidden = true }
        node.minItems = object["minItems"]?.numberValue.map { Int($0) }
        node.maxItems = object["maxItems"]?.numberValue.map { Int($0) }

        if case let .object(properties)? = object["properties"] {
            node.hasProperties = true
            for (key, value) in properties {
                node.properties.append((key, try compile(value, at: "\(location)/properties/\(escape(key))")))
            }
        }
        if case let .array(required)? = object["required"] { node.required = required.compactMap(\.stringValue) }
        switch object["additionalProperties"] {
        case .bool(false)?: node.additional = .strict
        case .bool(true)?: node.additional = .passthrough
        case let .object(schema)? where schema.isEmpty: node.additional = .passthrough
        case let schema?: node.additional = .schema(try compile(schema, at: "\(location)/additionalProperties"))
        case nil: node.additional = .strip
        }
        if let names = object["propertyNames"] {
            node.propertyNames = try compile(names, at: "\(location)/propertyNames")
        }
        if case let .array(options)? = object["anyOf"] {
            node.anyOf = try options.enumerated().map { try compile($0.element, at: "\(location)/anyOf/\($0.offset)") }
        }
        if case let .array(options)? = object["oneOf"] {
            node.oneOf = try options.enumerated().map { try compile($0.element, at: "\(location)/oneOf/\($0.offset)") }
        }
        if case let .array(options)? = object["allOf"] {
            node.allOf = try options.enumerated().map { try compile($0.element, at: "\(location)/allOf/\($0.offset)") }
        }
        if let not = object["not"] { node.not = try compile(not, at: "\(location)/not") }
        return node
    }

    private func escape(_ key: String) -> String {
        key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    /// Compiles every referenced location, including references found inside
    /// referenced schemas.
    mutating func resolvePendingReferences() throws {
        while let reference = pending.popLast() {
            if compiled[reference] != nil { continue }
            guard JavaScript.startsWith(reference, "#") else { throw SchemaDocumentError.unresolvedReference(reference) }
            let pointer = String(reference.dropFirst())
            let target = pointer.isEmpty ? document : document.value(atPath: pointer.removingPercentEncoding ?? pointer)
            if target.isUndefined { throw SchemaDocumentError.unresolvedReference(reference) }
            compiled[reference] = try compile(target, at: reference)
        }
    }
}

// MARK: - Validation

private struct SchemaValidator {
    let definitions: [String: SchemaNode]

    /// Validates `value` against `node`, appending zod-style issues. Returns
    /// the parsed value; it is only meaningful when no issue was added.
    func check(_ node: SchemaNode, _ value: JSONValue, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        if node.acceptsAnything { return value }
        if let embedded = node.embedded {
            return SchemaValidator(definitions: embedded.definitions).check(embedded.root, value, path: path, issues: &issues)
        }
        if node.rejectsEverything {
            issues.append(invalidType("never", value, path))
            return value
        }
        if let reference = node.reference {
            guard let target = definitions[reference] else { return value }
            return check(target, value, path: path, issues: &issues)
        }
        if let options = node.anyOf {
            return checkAnyOf(options, value, path: path, issues: &issues)
        }
        if let options = node.oneOf {
            return checkOneOf(options, value, path: path, issues: &issues)
        }
        var output = value
        if let parts = node.allOf {
            for part in parts {
                let parsed = check(part, value, path: path, issues: &issues)
                output = merge(output, parsed)
            }
            if node.types == nil, node.constValue == nil, node.enumValues == nil, !node.hasProperties { return output }
        }
        if let not = node.not {
            var ignored: [SchemaIssue] = []
            _ = check(not, value, path: path, issues: &ignored)
            if ignored.isEmpty {
                issues.append(SchemaIssue(code: "custom", path: path, message: "Invalid input"))
                return value
            }
        }
        if let constant = node.constValue {
            if !sameValue(value, constant) {
                issues.append(SchemaIssue(code: "invalid_value", path: path, message: "Invalid input: expected \(describe(constant))"))
            }
            return value
        }
        if let values = node.enumValues {
            if !values.contains(where: { sameValue(value, $0) }) {
                let message = values.count == 1
                    ? "Invalid input: expected \(describe(values[0]))"
                    : "Invalid option: expected one of \(values.map(describe).joined(separator: "|"))"
                issues.append(SchemaIssue(code: "invalid_value", path: path, message: message))
            }
            return value
        }
        if let types = node.types {
            let concrete = types.filter { $0 != "null" }
            if types.contains("null"), value.isNull { return value }
            if concrete.count > 1 {
                for type in concrete where matches(type, value) {
                    return checkTyped(type, node, value, path: path, issues: &issues)
                }
                issues.append(SchemaIssue(code: "invalid_union", path: path, message: "Invalid input"))
                return value
            }
            if let type = concrete.first {
                return checkTyped(type, node, value, path: path, issues: &issues)
            }
            issues.append(invalidType("null", value, path))
            return value
        }
        // No type: apply whatever keywords fit the value, as JSON Schema does.
        switch value {
        case .string: return checkTyped("string", node, value, path: path, issues: &issues)
        case .number: return checkTyped("number", node, value, path: path, issues: &issues)
        case .array: return checkTyped("array", node, value, path: path, issues: &issues)
        case .object: return node.hasProperties || node.propertyNames != nil || node.required.count > 0
            ? checkTyped("object", node, value, path: path, issues: &issues) : value
        default: return value
        }
    }

    private func matches(_ type: String, _ value: JSONValue) -> Bool {
        switch (type, value) {
        case ("string", .string), ("boolean", .bool), ("null", .null), ("array", .array), ("object", .object): true
        case let ("number", .number(number)): number.isFinite
        case let ("integer", .number(number)): number.isFinite && number.rounded(.towardZero) == number
        default: false
        }
    }

    private func checkTyped(_ type: String, _ node: SchemaNode, _ value: JSONValue, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        switch type {
        case "string":
            guard case let .string(string) = value else {
                issues.append(invalidType("string", value, path))
                return value
            }
            return checkString(node, string, path: path, issues: &issues)
        case "number", "integer":
            guard case let .number(number) = value, number.isFinite else {
                issues.append(invalidType("number", value, path))
                return value
            }
            if type == "integer", number.rounded(.towardZero) != number {
                issues.append(SchemaIssue(code: "invalid_type", path: path, message: "Invalid input: expected int, received number"))
                return value
            }
            checkNumber(node, number, isInteger: type == "integer", path: path, issues: &issues)
            return value
        case "boolean":
            if value.boolValue == nil { issues.append(invalidType("boolean", value, path)) }
            return value
        case "null":
            if !value.isNull { issues.append(invalidType("null", value, path)) }
            return value
        case "array":
            guard case let .array(array) = value else {
                issues.append(invalidType(node.prefixItems == nil ? "array" : "tuple", value, path))
                return value
            }
            return checkArray(node, array, path: path, issues: &issues)
        case "object":
            guard case let .object(object) = value else {
                issues.append(invalidType(node.propertyNames == nil ? "object" : "record", value, path))
                return value
            }
            return node.propertyNames == nil
                ? checkObject(node, object, path: path, issues: &issues)
                : checkRecord(node, object, path: path, issues: &issues)
        default:
            return value
        }
    }

    private func checkString(_ node: SchemaNode, _ string: String, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        var output = JSONValue.string(string)
        // zod 4.6 measures string length in code points, not UTF-16 units.
        let length = string.unicodeScalars.count
        for check in node.stringChecks {
            switch check {
            case let .length(expected):
                if length < expected {
                    issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected string to have exactly \(expected) characters"))
                } else if length > expected {
                    issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected string to have exactly \(expected) characters"))
                }
            case let .minLength(minimum) where length < minimum:
                issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected string to have >=\(minimum) characters"))
            case let .maxLength(maximum) where length > maximum:
                issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected string to have <=\(maximum) characters"))
            case let .pattern(source, regex, format):
                if !(regex?.test(string) ?? false) {
                    let message = format.flatMap(Self.formatMessage) ?? "Invalid string: must match pattern /\(source)/"
                    issues.append(SchemaIssue(code: "invalid_format", path: path, message: message))
                }
            case .url:
                let trimmed = JavaScript.trim(string)
                if WHATWGURL.canParse(trimmed) {
                    output = .string(trimmed)
                } else {
                    issues.append(SchemaIssue(code: "invalid_format", path: path, message: "Invalid URL"))
                }
            default:
                break
            }
        }
        return output
    }

    /// zod's message for a failed string format, by JSON Schema format name.
    private static func formatMessage(_ format: String) -> String? {
        let names: [String: String] = [
            "email": "email address", "uri": "URL", "url": "URL", "emoji": "emoji", "uuid": "UUID", "guid": "GUID",
            "nanoid": "nanoid", "cuid": "cuid", "cuid2": "cuid2", "ulid": "ULID", "xid": "XID", "ksuid": "KSUID",
            "date-time": "ISO datetime", "date": "ISO date", "time": "ISO time", "duration": "ISO duration",
            "ipv4": "IPv4 address", "ipv6": "IPv6 address", "cidrv4": "IPv4 range", "cidrv6": "IPv6 range",
            "base64": "base64-encoded string", "base64url": "base64url-encoded string", "e164": "E.164 number",
            "jwt": "JWT",
        ]
        return names[format].map { "Invalid \($0)" }
    }

    private static let maxSafeInteger = 9_007_199_254_740_991.0

    private func checkNumber(_ node: SchemaNode, _ number: Double, isInteger: Bool, path: [JSONValue], issues: inout [SchemaIssue]) {
        func origin(_ bound: Double) -> String {
            isInteger && abs(bound) == Self.maxSafeInteger ? "int" : "number"
        }
        if let bound = node.exclusiveMinimum, !(number > bound) {
            issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected \(origin(bound)) to be >\(JavaScript.numberToString(bound))"))
        } else if let bound = node.minimum, !(number >= bound) {
            issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected \(origin(bound)) to be >=\(JavaScript.numberToString(bound))"))
        }
        if let bound = node.exclusiveMaximum, !(number < bound) {
            issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected \(origin(bound)) to be <\(JavaScript.numberToString(bound))"))
        } else if let bound = node.maximum, !(number <= bound) {
            issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected \(origin(bound)) to be <=\(JavaScript.numberToString(bound))"))
        }
        if let divisor = node.multipleOf, JavaScript.floatSafeRemainder(number, divisor) != 0 {
            issues.append(SchemaIssue(code: "not_multiple_of", path: path, message: "Invalid number: must be a multiple of \(JavaScript.numberToString(divisor))"))
        }
    }

    private func checkArray(_ node: SchemaNode, _ array: JSONArray, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        if let prefix = node.prefixItems {
            // A tuple checks its length first and stops there when it is wrong.
            let minimum = node.minItems ?? prefix.count
            if array.count < minimum {
                issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected array to have >=\(minimum) items"))
                return .array(array)
            }
            if let maximum = node.maxItems ?? (node.itemsForbidden ? prefix.count : nil), array.count > maximum {
                issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected array to have <=\(maximum) items"))
                return .array(array)
            }
            var output: [JSONValue] = []
            for (index, element) in array.enumerated() {
                let elementPath = path + [.number(Double(index))]
                if index < prefix.count {
                    output.append(check(prefix[index], element, path: elementPath, issues: &issues))
                } else if let rest = node.items {
                    output.append(check(rest, element, path: elementPath, issues: &issues))
                } else {
                    output.append(element)
                }
            }
            return .array(JSONArray(output))
        }

        var output: [JSONValue] = []
        for (index, element) in array.enumerated() {
            if let items = node.items {
                output.append(check(items, element, path: path + [.number(Double(index))], issues: &issues))
            } else {
                output.append(element)
            }
        }
        if let minimum = node.minItems, let maximum = node.maxItems, minimum == maximum {
            if array.count < minimum {
                issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected array to have exactly \(minimum) items"))
            } else if array.count > maximum {
                issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected array to have exactly \(maximum) items"))
            }
        } else {
            if let minimum = node.minItems, array.count < minimum {
                issues.append(SchemaIssue(code: "too_small", path: path, message: "Too small: expected array to have >=\(minimum) items"))
            }
            if let maximum = node.maxItems, array.count > maximum {
                issues.append(SchemaIssue(code: "too_big", path: path, message: "Too big: expected array to have <=\(maximum) items"))
            }
        }
        return .array(JSONArray(output))
    }

    private func checkObject(_ node: SchemaNode, _ object: JSONObject, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        var output = JSONObject()
        let required = Set(node.required.map(ExactKey.init))
        var known: Set<ExactKey> = []
        for (key, property) in node.properties {
            known.insert(ExactKey(key))
            let keyPath = path + [.string(key)]
            if let value = object[key], !(value.isUndefined && !required.contains(ExactKey(key))) {
                output[key] = check(property, value, path: keyPath, issues: &issues)
            } else if object[key] != nil, property.defaultValue == nil {
                // An optional key present with `undefined` is accepted and kept.
                output[key] = .undefined
            } else if let defaultValue = property.defaultValue {
                output[key] = defaultValue
            } else if required.contains(ExactKey(key)) {
                if property.acceptsUndefined {
                    issues.append(SchemaIssue(code: "invalid_type", path: keyPath, message: "Invalid input: expected nonoptional, received undefined"))
                } else {
                    _ = check(property, .undefined, path: keyPath, issues: &issues)
                }
            }
        }
        // Required keys without a property schema still must be present.
        for key in node.required where !known.contains(ExactKey(key)) && !object.hasKey(key) {
            issues.append(SchemaIssue(code: "invalid_type", path: path + [.string(key)], message: "Invalid input: expected nonoptional, received undefined"))
        }
        var unrecognized: [String] = []
        for (key, value) in object where !known.contains(ExactKey(key)) {
            switch node.additional {
            case .strip: break
            case .strict: unrecognized.append(key)
            case .passthrough: output[key] = value
            case let .schema(schema): output[key] = check(schema, value, path: path + [.string(key)], issues: &issues)
            }
        }
        if !unrecognized.isEmpty { issues.append(unrecognizedKeys(unrecognized, path)) }
        return .object(output)
    }

    private func checkRecord(_ node: SchemaNode, _ object: JSONObject, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        let valueSchema: SchemaNode? = switch node.additional {
        case let .schema(schema): schema
        default: nil
        }
        var output = JSONObject()
        let names = node.propertyNames!
        if let keys = names.enumValues {
            // An enum key schema makes the record exhaustive, like z.record(z.enum(...)).
            let required = Set(node.required.map(ExactKey.init))
            var unrecognized: [String] = []
            for key in keys.compactMap(\.stringValue) {
                let keyPath = path + [.string(key)]
                if let value = object[key] {
                    output[key] = valueSchema.map { check($0, value, path: keyPath, issues: &issues) } ?? value
                } else if required.contains(ExactKey(key)), let valueSchema {
                    if valueSchema.acceptsUndefined {
                        issues.append(SchemaIssue(code: "invalid_type", path: keyPath, message: "Invalid input: expected nonoptional, received undefined"))
                    } else {
                        _ = check(valueSchema, .undefined, path: keyPath, issues: &issues)
                    }
                }
            }
            for (key, _) in object where !keys.contains(.string(key)) { unrecognized.append(key) }
            if !unrecognized.isEmpty { issues.append(unrecognizedKeys(unrecognized, path)) }
            return .object(output)
        }
        for (key, value) in object {
            let keyPath = path + [.string(key)]
            var keyIssues: [SchemaIssue] = []
            _ = check(names, .string(key), path: [], issues: &keyIssues)
            if !keyIssues.isEmpty {
                issues.append(SchemaIssue(code: "invalid_key", path: keyPath, message: "Invalid key in record"))
                continue
            }
            output[key] = valueSchema.map { check($0, value, path: keyPath, issues: &issues) } ?? value
        }
        return .object(output)
    }

    private func checkAnyOf(_ options: [SchemaNode], _ value: JSONValue, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        // zod's nullable(): `anyOf` of one schema and `{ "type": "null" }`.
        if options.count == 2, let nullIndex = options.firstIndex(where: { $0.types == ["null"] && $0.isPlainType }) {
            if value.isNull { return value }
            return check(options[1 - nullIndex], value, path: path, issues: &issues)
        }
        return checkUnion(options, value, path: path, issues: &issues)
    }

    private func checkUnion(_ options: [SchemaNode], _ value: JSONValue, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        for option in options {
            var optionIssues: [SchemaIssue] = []
            let parsed = check(option, value, path: path, issues: &optionIssues)
            if optionIssues.isEmpty { return parsed }
        }
        issues.append(SchemaIssue(code: "invalid_union", path: path, message: "Invalid input"))
        return value
    }

    private func checkOneOf(_ options: [SchemaNode], _ value: JSONValue, path: [JSONValue], issues: inout [SchemaIssue]) -> JSONValue {
        guard let discriminator = Self.discriminator(of: options) else {
            return checkUnion(options, value, path: path, issues: &issues)
        }
        guard case let .object(object) = value else {
            issues.append(invalidType("object", value, path))
            return value
        }
        let tag = object[discriminator] ?? .undefined
        for option in options {
            let property = option.properties.first { $0.key == discriminator }!.node
            if let constant = property.constValue, sameValue(tag, constant) {
                return check(option, value, path: path, issues: &issues)
            }
        }
        let expected = options.compactMap { $0.properties.first { $0.key == discriminator }?.node.constValue }
            .map { "'\($0.javaScriptString)'" }.joined(separator: " | ")
        issues.append(SchemaIssue(code: "invalid_union", path: path + [.string(discriminator)], message: "Invalid discriminator value. Expected \(expected)"))
        return value
    }

    /// The property every branch fixes with `const`, if any.
    private static func discriminator(of options: [SchemaNode]) -> String? {
        guard let first = options.first else { return nil }
        for (key, node) in first.properties where node.constValue != nil {
            let shared = options.allSatisfy { option in
                option.properties.contains { $0.key == key && $0.node.constValue != nil }
            }
            if shared { return key }
        }
        return nil
    }

    private func merge(_ a: JSONValue, _ b: JSONValue) -> JSONValue {
        guard case var .object(left) = a, case let .object(right) = b else { return b }
        for (key, value) in right { left[key] = value }
        return .object(left)
    }

    private func sameValue(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case (.array, .array), (.object, .object): a == b
        default: a.strictEquals(b)
        }
    }

    /// A value in an issue message: strings quoted, everything else as JSON.
    private func describe(_ value: JSONValue) -> String {
        if case let .string(string) = value { return "\"\(string)\"" }
        return value.stringified() ?? value.javaScriptString
    }

    private func invalidType(_ expected: String, _ value: JSONValue, _ path: [JSONValue]) -> SchemaIssue {
        SchemaIssue(code: "invalid_type", path: path, message: "Invalid input: expected \(expected), received \(Self.receivedType(value))")
    }

    private func unrecognizedKeys(_ keys: [String], _ path: [JSONValue]) -> SchemaIssue {
        let list = keys.map { "\"\($0)\"" }.joined(separator: ", ")
        return SchemaIssue(code: "unrecognized_keys", path: path, message: keys.count == 1 ? "Unrecognized key: \(list)" : "Unrecognized keys: \(list)")
    }

    /// zod's name for the type it received.
    static func receivedType(_ value: JSONValue) -> String {
        switch value {
        case .undefined: "undefined"
        case .null: "null"
        case .bool: "boolean"
        case let .number(number): number.isNaN ? "NaN" : number.isInfinite ? "Infinity" : "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }
}

extension SchemaNode {
    /// True when the node has only a `type` keyword.
    var isPlainType: Bool {
        constValue == nil && enumValues == nil && anyOf == nil && oneOf == nil && allOf == nil && reference == nil
    }
}

extension JavaScript {
    /// zod's `floatSafeRemainder`, used for `multipleOf`: both numbers are
    /// scaled to integers by their decimal digit count before `%`.
    static func floatSafeRemainder(_ value: Double, _ step: Double) -> Double {
        func decimals(_ number: Double) -> Int {
            let text = numberToString(number)
            guard let dot = text.firstIndex(of: ".") else { return 0 }
            return text[text.index(after: dot)...].count
        }
        let valueDecimals = decimals(value)
        let stepText = numberToString(step)
        var stepDecimals = decimals(step)
        if stepDecimals == 0, let range = stepText.range(of: "e-") {
            // Upstream reads only one digit of the exponent.
            if let digit = stepText[range.upperBound...].first, digit.isNumber { stepDecimals = Int(String(digit))! }
        }
        let count = max(valueDecimals, stepDecimals)
        let scale = pow(10.0, Double(count))
        let valueInteger = (value * scale).rounded()
        let stepInteger = (step * scale).rounded()
        return valueInteger.truncatingRemainder(dividingBy: stepInteger) / scale
    }
}

/// The issues of a value that failed ``JSONSchema/parse(_:)``, like a `ZodError`.
public struct SchemaError: Error, Sendable, Equatable, CustomStringConvertible {
    public var issues: [SchemaIssue]
    public var description: String { issues.map(\.description).joined(separator: "; ") }
}

extension JSONSchema {
    /// Validates a value and returns the parsed data, like zod's `parse`.
    public func parse(_ value: JSONValue) throws -> JSONValue {
        let result = validate(value)
        guard result.success else { throw SchemaError(issues: result.issues) }
        return result.data
    }
}
