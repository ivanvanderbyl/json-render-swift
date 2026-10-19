import Foundation

/// Prop expressions: dynamic values in element props.
///
/// - `{ "$state": "/path" }` reads state.
/// - `{ "$item": "field" }` reads the current repeat item (`""` for the whole item).
/// - `{ "$index": true }` is the current repeat index.
/// - `{ "$bindState": "/path" }` and `{ "$bindItem": "field" }` read like
///   `$state` and `$item` and also expose a write-back path (see ``bindings(for:in:)``).
/// - `{ "$cond": condition, "$then": value, "$else": value }` picks a branch.
/// - `{ "$computed": "name", "args": { ... } }` calls a registered function.
/// - `{ "$template": "Hello ${/name}" }` interpolates state and item fields.
/// - Objects with a registered directive key resolve through that directive.
/// - Arrays and other objects resolve recursively; anything else is literal.
///
/// The first matching form wins, in the order listed.
public enum PropExpression {
    /// Resolves one value, like upstream `resolvePropValue`. Throws when a
    /// computed function or directive throws, when an object has two
    /// directive keys, or when a condition is malformed.
    public static func resolve(_ value: JSONValue, in context: ResolutionContext) throws -> JSONValue {
        guard case let .object(object) = value else {
            if case let .array(array) = value {
                return .array(JSONArray(try array.map { try resolve($0, in: context) }))
            }
            return value
        }

        if case let .string(path)? = object["$state"] {
            return context.state.value(atPath: path)
        }
        if case let .string(path)? = object["$item"] {
            if context.repeatItem.isUndefined { return .undefined }
            return path.isEmpty ? context.repeatItem : context.repeatItem.value(atPath: path)
        }
        if object["$index"] == true {
            return context.repeatIndex.map { .number(Double($0)) } ?? .undefined
        }
        if case let .string(path)? = object["$bindState"] {
            return context.state.value(atPath: path)
        }
        if case let .string(path)? = object["$bindItem"] {
            guard let resolved = bindItemPath(path, in: context) else { return .undefined }
            return context.state.value(atPath: resolved)
        }
        if let condition = object["$cond"], let then = object["$then"], let otherwise = object["$else"] {
            return try resolve(Visibility.evaluate(condition, in: context) ? then : otherwise, in: context)
        }
        if case let .string(name)? = object["$computed"] {
            guard let function = context.functions[name] else {
                WarnedComputedFunctions.shared.warnOnce(name)
                return .undefined
            }
            var arguments = JSONObject()
            if let args = object["args"], args.isTruthy {
                for (key, argument) in try JavaScript.entries(args) {
                    arguments[key] = try resolve(argument, in: context)
                }
            }
            return try function(arguments)
        }
        if case let .string(template)? = object["$template"] {
            return .string(interpolateTemplate(template, in: context))
        }
        if let directive = try context.directives?.find(in: object) {
            return try directive.resolve(value, context)
        }
        var resolved = JSONObject()
        for (key, member) in object {
            resolved[key] = try resolve(member, in: context)
        }
        return .object(resolved)
    }

    /// Resolves every prop of an element, like upstream `resolveElementProps`.
    public static func resolveProps(_ props: JSONObject, in context: ResolutionContext) throws -> JSONObject {
        var resolved = JSONObject()
        for (key, value) in props {
            resolved[key] = try resolve(value, in: context)
        }
        return resolved
    }

    /// Maps each prop that uses `$bindState` or `$bindItem` to its absolute
    /// state path, like upstream `resolveBindings`. Returns `nil` when no prop
    /// is bound.
    public static func bindings(for props: JSONObject, in context: ResolutionContext) -> [String: String]? {
        var bindings: [String: String]?
        for (key, value) in props {
            guard case let .object(object) = value else { continue }
            if case let .string(path)? = object["$bindState"] {
                bindings = (bindings ?? [:]).merging([key: path]) { $1 }
            } else if case let .string(path)? = object["$bindItem"], let resolved = bindItemPath(path, in: context) {
                bindings = (bindings ?? [:]).merging([key: resolved]) { $1 }
            }
        }
        return bindings
    }

    /// Resolves one action param, like upstream `resolveActionParam`:
    /// `{ "$item": "field" }` gives the field's absolute state path rather than
    /// its value, so it can be passed to `setState`.
    public static func resolveActionParam(_ value: JSONValue, in context: ResolutionContext) throws -> JSONValue {
        if case let .object(object) = value {
            if case let .string(path)? = object["$item"] {
                return bindItemPath(path, in: context).map(JSONValue.string) ?? .undefined
            }
            if object["$index"] == true {
                return context.repeatIndex.map { .number(Double($0)) } ?? .undefined
            }
        }
        return try resolve(value, in: context)
    }

    /// Clears the record of unknown `$computed` names already warned about.
    static func resetWarnedComputedFunctions() {
        WarnedComputedFunctions.shared.reset()
    }

    /// `$bindItem` and `$item` param paths: `""` is the item itself.
    private static func bindItemPath(_ itemPath: String, in context: ResolutionContext) -> String? {
        guard let base = context.repeatBasePath else {
            Diagnostics.warn("$bindItem used outside repeat scope: \"\(itemPath)\"")
            return nil
        }
        return itemPath.isEmpty ? base : base + "/" + itemPath
    }

    /// Replaces each `${reference}`. Absolute paths read state; bare names read
    /// the repeat item first and then `/<name>` in state. Missing, `null` and
    /// `undefined` values become "".
    private static func interpolateTemplate(_ template: String, in context: ResolutionContext) -> String {
        JavaScript.replacePlaceholders(in: template) { reference in
            if JavaScript.startsWith(reference, "/") {
                let value = context.state.value(atPath: reference)
                return value.isNullish ? "" : value.javaScriptString
            }
            if !context.repeatItem.isUndefined {
                let fromItem = context.repeatItem.value(atPath: reference)
                if !fromItem.isNullish { return fromItem.javaScriptString }
            }
            let value = context.state.value(atPath: "/" + reference)
            return value.isNullish ? "" : value.javaScriptString
        }
    }
}

/// Upstream warns once per unknown `$computed` name and stops remembering new
/// names after 100, so the record cannot grow without bound.
final class WarnedComputedFunctions: @unchecked Sendable {
    static let shared = WarnedComputedFunctions()
    static let limit = 100

    private let lock = NSLock()
    private var names: Set<ExactKey> = []

    func warnOnce(_ name: String) {
        let shouldWarn: Bool = lock.withLock {
            if names.contains(ExactKey(name)) { return false }
            if names.count < Self.limit { names.insert(ExactKey(name)) }
            return true
        }
        if shouldWarn { Diagnostics.warn("Unknown $computed function: \"\(name)\"") }
    }

    func reset() { lock.withLock { names.removeAll() } }
}

extension JavaScript {
    /// `template.replace(/\$\{([^}]+)\}/g, replace)`.
    static func replacePlaceholders(in template: String, _ replace: (String) -> String) -> String {
        let units = Array(template.utf16)
        var output: [UInt16] = []
        output.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            if units[index] == 0x24, index + 1 < units.count, units[index + 1] == 0x7B {
                var end = index + 2
                while end < units.count, units[end] != 0x7D { end += 1 }
                if end < units.count, end > index + 2 {
                    let reference = String(decoding: units[(index + 2)..<end], as: UTF16.self)
                    output.append(contentsOf: replace(reference).utf16)
                    index = end + 1
                    continue
                }
            }
            output.append(units[index])
            index += 1
        }
        return String(decoding: output, as: UTF16.self)
    }
}
