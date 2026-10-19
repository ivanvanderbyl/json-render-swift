import JSONRender
import JSONRenderUI

/// Reading props the way the upstream components do: `p.x ?? fallback`
/// treats null and undefined as missing, and a prop of the wrong type is
/// ignored, as React Native ignores an invalid style value.
extension ComponentContext {
    func number(_ key: String) -> Double? {
        if case let .number(value) = props[key] ?? .undefined { return value }
        return nil
    }

    func string(_ key: String) -> String? { props[key]?.stringValue }

    func color(_ key: String) -> CSSColor? { string(key).flatMap(CSSColor.init) }

    /// `!!p.x`.
    func truthy(_ key: String) -> Bool { props[key]?.isTruthy ?? false }

    /// `p.x ?? fallback` for a boolean option.
    func flag(_ key: String, default fallback: Bool) -> Bool {
        let value = props[key] ?? .undefined
        return value.isNullish ? fallback : value.isTruthy
    }

    /// The prop as React renders it as a text child.
    func text(_ key: String) throws -> String { try ReactText.string(props[key] ?? .undefined) }

    /// The text for `p.x && <Text>{p.x}</Text>`: nil when the prop is falsy.
    func optionalText(_ key: String) throws -> String? { truthy(key) ? try text(key) : nil }

    /// `table[p.x ?? fallback]` for a string-keyed style table.
    func option<Value>(_ key: String, default fallback: String, in table: [String: Value]) -> Value? {
        let value = props[key] ?? .undefined
        return table[value.isNullish ? fallback : value.javaScriptString]
    }

    /// An enum prop, or the fallback when it is missing or not a known case.
    func choice<Value: RawRepresentable<String>>(_ key: String, default fallback: Value) -> Value {
        string(key).flatMap { Value(rawValue: $0) } ?? fallback
    }
}

/// Text the way React renders a child: strings as written, numbers as
/// JavaScript prints them, nothing for booleans, null and undefined, arrays
/// joined, and an error for objects.
enum ReactText {
    struct ObjectChildError: Error, CustomStringConvertible {
        let keys: [String]
        var description: String {
            "Objects are not valid as a React child (found: object with keys {\(keys.joined(separator: ", "))}). "
                + "If you meant to render a collection of children, use an array instead."
        }
    }

    static func string(_ value: JSONValue) throws -> String {
        switch value {
        case let .string(text): return text
        case .number: return value.javaScriptString
        case .bool, .null, .undefined: return ""
        case let .array(items): return try items.map(string).joined()
        case let .object(object): throw ObjectChildError(keys: object.keys)
        }
    }
}
