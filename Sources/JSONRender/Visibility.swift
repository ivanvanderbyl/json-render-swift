/// Visibility conditions: the `visible` field of an element, and the
/// condition of a `$cond` expression.
///
/// A condition is `true` or `false`; a single condition object with exactly
/// one of `$state`, `$item` or `$index` and at most one comparison operator
/// (`eq`, `neq`, `gt`, `gte`, `lt`, `lte`) plus an optional `not: true`; an
/// array of single conditions (all must hold); `{ "$and": [...] }`; or
/// `{ "$or": [...] }`.
public enum Visibility {
    /// Evaluates a condition, like upstream `evaluateVisibility`. `undefined`
    /// means visible. Throws the TypeError upstream throws for malformed
    /// conditions, such as `null` or a non-array `$and`.
    ///
    /// With several operators in one condition only the first applies, in the
    /// order eq, neq, gt, gte, lt, lte. `eq` and `neq` use `===`, so objects
    /// and arrays are equal only when they are the same value from state.
    /// `gt`, `gte`, `lt` and `lte` are false unless both sides are numbers.
    public static func evaluate(_ condition: JSONValue, in context: ResolutionContext) throws -> Bool {
        switch condition {
        case .undefined:
            return true
        case let .bool(value):
            return value
        case let .array(conditions):
            for single in conditions where try !evaluateCondition(single, in: context) { return false }
            return true
        case let .object(object):
            if let children = object["$and"] {
                for child in try iterate(children, method: "every", on: "condition.$and")
                where try !evaluate(child, in: context) {
                    return false
                }
                return true
            }
            if let children = object["$or"] {
                for child in try iterate(children, method: "some", on: "condition.$or")
                where try evaluate(child, in: context) {
                    return true
                }
                return false
            }
            return try evaluateCondition(condition, in: context)
        default:
            return try evaluateCondition(condition, in: context)
        }
    }

    /// `array.every` / `array.some` on a value that must be an array.
    static func iterate(_ value: JSONValue, method: String, on expression: String) throws -> JSONArray {
        switch value {
        case let .array(array):
            return array
        case .undefined, .null:
            throw JavaScriptError.typeError("Cannot read properties of \(value.javaScriptString) (reading '\(method)')")
        default:
            throw JavaScriptError.typeError("\(expression).\(method) is not a function")
        }
    }

    /// `"key" in value`: throws for primitives, like the JavaScript `in`
    /// operator. Arrays have no `$`-prefixed members.
    private static func has(_ key: String, _ value: JSONValue) throws -> Bool {
        switch value {
        case let .object(object): return object.hasKey(key)
        case .array: return false
        default:
            throw JavaScriptError.typeError("Cannot use 'in' operator to search for '\(key)' in \(value.javaScriptString)")
        }
    }

    private static func member(_ key: String, _ value: JSONValue) -> JSONValue {
        value.objectValue?[key] ?? .undefined
    }

    /// The left-hand side of a single condition.
    private static func conditionValue(_ condition: JSONValue, in context: ResolutionContext) throws -> JSONValue {
        if try has("$index", condition) {
            return context.repeatIndex.map { .number(Double($0)) } ?? .undefined
        }
        if try has("$item", condition) {
            if context.repeatItem.isUndefined { return .undefined }
            let path = member("$item", condition)
            if path == "" { return context.repeatItem }
            return try DynamicValue.readState(context.repeatItem, path: path)
        }
        return try DynamicValue.readState(context.state, path: member("$state", condition))
    }

    /// A comparison operand: `{ "$state": "/path" }` reads state, anything else
    /// is a literal.
    private static func comparisonValue(_ value: JSONValue, in context: ResolutionContext) -> JSONValue {
        if case let .object(object) = value, case let .string(path)? = object["$state"] {
            return context.state.value(atPath: path)
        }
        return value
    }

    private static func evaluateCondition(_ condition: JSONValue, in context: ResolutionContext) throws -> Bool {
        let value = try conditionValue(condition, in: context)
        let result: Bool
        func numeric(_ compare: (Double, Double) -> Bool, _ operand: JSONValue) -> Bool {
            guard case let .number(left) = value, case let .number(right) = comparisonValue(operand, in: context) else {
                return false
            }
            return compare(left, right)
        }
        if case let operand = member("eq", condition), !operand.isUndefined {
            result = value.strictEquals(comparisonValue(operand, in: context))
        } else if case let operand = member("neq", condition), !operand.isUndefined {
            result = !value.strictEquals(comparisonValue(operand, in: context))
        } else if case let operand = member("gt", condition), !operand.isUndefined {
            result = numeric(>, operand)
        } else if case let operand = member("gte", condition), !operand.isUndefined {
            result = numeric(>=, operand)
        } else if case let operand = member("lt", condition), !operand.isUndefined {
            result = numeric(<, operand)
        } else if case let operand = member("lte", condition), !operand.isUndefined {
            result = numeric(<=, operand)
        } else {
            result = value.isTruthy
        }
        return member("not", condition) == true ? !result : result
    }

    /// True when the condition references `$item` or `$index` anywhere, like
    /// upstream `conditionUsesItemScope`.
    public static func usesItemScope(_ condition: JSONValue) throws -> Bool {
        switch condition {
        case let .array(conditions):
            for part in conditions where try usesItemScope(part) { return true }
            return false
        case let .object(object):
            if object.hasKey("$item") || object.hasKey("$index") { return true }
            if let parts = object["$and"] {
                for part in try iterate(parts, method: "some", on: "condition.$and") where try usesItemScope(part) {
                    return true
                }
                return false
            }
            if let parts = object["$or"] {
                for part in try iterate(parts, method: "some", on: "condition.$or") where try usesItemScope(part) {
                    return true
                }
                return false
            }
            return false
        default:
            return false
        }
    }

    /// Splits a repeat container's condition into a container gate and a
    /// per-item filter, like upstream `splitRepeatVisibility`.
    ///
    /// Conjuncts of a top-level array or `$and` that reference `$item` or
    /// `$index` filter items; the rest gate the container. Any other
    /// item-scoped condition, including an `$or` that mixes scopes, applies
    /// entirely per item.
    public static func splitRepeatVisibility(_ condition: JSONValue) throws -> (container: JSONValue, itemFilter: JSONValue) {
        if try condition.isUndefined || !usesItemScope(condition) {
            return (condition, .undefined)
        }
        func partition(_ parts: JSONArray) throws -> (container: JSONValue, itemFilter: JSONValue) {
            var container: [JSONValue] = []
            var item: [JSONValue] = []
            for part in parts {
                if try usesItemScope(part) { item.append(part) } else { container.append(part) }
            }
            return (
                container.isEmpty ? .undefined : ["$and": .array(JSONArray(container))],
                item.isEmpty ? .undefined : ["$and": .array(JSONArray(item))]
            )
        }
        if case let .array(parts) = condition { return try partition(parts) }
        if case let .object(object) = condition, let parts = object["$and"] {
            return try partition(try iterate(parts, method: "filter", on: "parts"))
        }
        return (.undefined, condition)
    }

    // MARK: Strict validation

    /// True when the condition matches upstream `VisibilityConditionStrictSchema`:
    /// a boolean; one strict single condition; an array of strict single
    /// conditions; or a strict `{ "$and": [...] }` / `{ "$or": [...] }` of
    /// valid conditions. Spec validation reports anything else as
    /// `invalid_visible`.
    public static func isValid(_ condition: JSONValue) -> Bool {
        switch condition {
        case .bool:
            return true
        case let .array(parts):
            return parts.allSatisfy(isStrictSingleCondition)
        case let .object(object):
            if isStrictSingleCondition(condition) { return true }
            for key in ["$and", "$or"] where object.keys == [key] {
                guard case let .array(children) = object[key]! else { return false }
                return children.allSatisfy(isValid)
            }
            return false
        default:
            return false
        }
    }

    private static let comparisonKeys: Set<String> = ["eq", "neq", "gt", "gte", "lt", "lte", "not"]

    private static func isStrictSingleCondition(_ condition: JSONValue) -> Bool {
        guard case let .object(object) = condition else { return false }
        let sources: [(String, (JSONValue) -> Bool)] = [
            ("$state", { $0.stringValue != nil }),
            ("$item", { $0.stringValue != nil }),
            ("$index", { $0 == true }),
        ]
        return sources.contains { source, isValidSource in
            guard let value = object[source], isValidSource(value) else { return false }
            return object.allSatisfy { key, member in
                if key == source { return true }
                guard comparisonKeys.contains(key) else { return false }
                return isValidOperand(key, member)
            }
        }
    }

    private static func isValidOperand(_ key: String, _ value: JSONValue) -> Bool {
        if value.isUndefined { return true }
        switch key {
        case "eq", "neq":
            return true
        case "not":
            return value == true
        default:
            switch value {
            case let .number(number): return number.isFinite
            case let .object(object): return object["$state"]?.stringValue != nil
            default: return false
            }
        }
    }

    // MARK: Helpers (upstream `visibility`)

    /// Always visible.
    public static let always: JSONValue = true
    /// Never visible.
    public static let never: JSONValue = false
    /// Visible when the state path is truthy.
    public static func when(_ path: String) -> JSONValue { ["$state": .string(path)] }
    /// Visible when the state path is falsy.
    public static func unless(_ path: String) -> JSONValue { ["$state": .string(path), "not": true] }
    public static func eq(_ path: String, _ value: JSONValue) -> JSONValue { ["$state": .string(path), "eq": value] }
    public static func neq(_ path: String, _ value: JSONValue) -> JSONValue { ["$state": .string(path), "neq": value] }
    public static func gt(_ path: String, _ value: JSONValue) -> JSONValue { ["$state": .string(path), "gt": value] }
    public static func gte(_ path: String, _ value: JSONValue) -> JSONValue { ["$state": .string(path), "gte": value] }
    public static func lt(_ path: String, _ value: JSONValue) -> JSONValue { ["$state": .string(path), "lt": value] }
    public static func lte(_ path: String, _ value: JSONValue) -> JSONValue { ["$state": .string(path), "lte": value] }
    /// All conditions must hold.
    public static func and(_ conditions: JSONValue...) -> JSONValue { ["$and": .array(JSONArray(conditions))] }
    /// At least one condition must hold.
    public static func or(_ conditions: JSONValue...) -> JSONValue { ["$or": .array(JSONArray(conditions))] }
}
