/// A JSON value with the JavaScript semantics json-render depends on.
///
/// json-render specs and state are plain JavaScript values. `JSONValue` keeps
/// the parts of JavaScript behaviour that change what renders:
///
/// - ``undefined`` is a value distinct from ``null``. It means "missing", for
///   example a state path that does not exist. It never appears in encoded
///   JSON: object members holding it are dropped and array elements holding it
///   encode as `null`, as `JSON.stringify` does.
/// - Numbers are `Double`, like JavaScript numbers.
/// - Arrays and objects have reference identity. ``strictEquals(_:)`` mirrors
///   JavaScript `===`, so two separately built objects are not strictly equal
///   even when their contents match. `==` compares contents.
/// - Object keys keep JavaScript property order: integer-like keys first in
///   ascending order, then other keys in insertion order.
public enum JSONValue: Sendable {
    case undefined
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array(JSONArray)
    case object(JSONObject)
}

// MARK: - Accessors

extension JSONValue {
    public var isUndefined: Bool {
        if case .undefined = self { return true }
        return false
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// True for `null` and `undefined`, like `value == null` in JavaScript.
    public var isNullish: Bool {
        switch self {
        case .undefined, .null: true
        default: false
        }
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var arrayValue: JSONArray? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: JSONObject? {
        if case let .object(value) = self { return value }
        return nil
    }

    /// True for arrays and objects, like `typeof value === "object" && value !== null`.
    public var isContainer: Bool {
        switch self {
        case .array, .object: true
        default: false
        }
    }

    /// Reads an object member, or `undefined` when the member is missing or the
    /// value is not an object. Writing to a non-object value does nothing.
    public subscript(key: String) -> JSONValue {
        get {
            if case let .object(object) = self { return object[key] ?? .undefined }
            return .undefined
        }
        set {
            guard case var .object(object) = self else { return }
            self = .undefined
            object[key] = newValue
            self = .object(object)
        }
    }

    /// Reads an array element, or `undefined` when out of range or not an array.
    public subscript(index: Int) -> JSONValue {
        if case let .array(array) = self, array.indices.contains(index) { return array[index] }
        return .undefined
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(JSONArray(elements)) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var object = JSONObject()
        for (key, value) in elements { object[key] = value }
        self = .object(object)
    }
}

// MARK: - Equality

extension JSONValue: Equatable {
    /// Structural equality. Strings compare by UTF-16 code units, as in
    /// JavaScript. Use ``strictEquals(_:)`` for JavaScript `===`.
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.undefined, .undefined), (.null, .null):
            true
        case let (.bool(a), .bool(b)):
            a == b
        case let (.number(a), .number(b)):
            a == b
        case let (.string(a), .string(b)):
            a.utf16.elementsEqual(b.utf16)
        case let (.array(a), .array(b)):
            a == b
        case let (.object(a), .object(b)):
            a == b
        default:
            false
        }
    }

    /// JavaScript `===`: primitives compare by value (NaN is never equal and
    /// `0 === -0`), arrays and objects compare by reference.
    public func strictEquals(_ other: JSONValue) -> Bool {
        switch (self, other) {
        case let (.array(a), .array(b)):
            a.isIdentical(to: b)
        case let (.object(a), .object(b)):
            a.isIdentical(to: b)
        default:
            self == other
        }
    }
}

extension JSONValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .undefined: "undefined"
        default: stringified() ?? "undefined"
        }
    }
}
