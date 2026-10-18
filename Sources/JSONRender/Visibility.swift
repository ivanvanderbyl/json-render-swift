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
    public static func evaluate(_ condition: JSONValue, in context: ResolutionContext) throws -> Bool { false }

    /// True when the condition references `$item` or `$index` anywhere, like
    /// upstream `conditionUsesItemScope`.
    public static func usesItemScope(_ condition: JSONValue) throws -> Bool { false }

    /// Splits a repeat container's condition into a container gate and a
    /// per-item filter, like upstream `splitRepeatVisibility`.
    public static func splitRepeatVisibility(_ condition: JSONValue) throws -> (container: JSONValue, itemFilter: JSONValue) {
        (.undefined, .undefined)
    }

    /// True when the condition matches upstream `VisibilityConditionStrictSchema`.
    public static func isValid(_ condition: JSONValue) -> Bool { false }

    // MARK: Helpers (upstream `visibility`)

    public static let always: JSONValue = true
    public static let never: JSONValue = false
    public static func when(_ path: String) -> JSONValue { .undefined }
    public static func unless(_ path: String) -> JSONValue { .undefined }
    public static func eq(_ path: String, _ value: JSONValue) -> JSONValue { .undefined }
    public static func neq(_ path: String, _ value: JSONValue) -> JSONValue { .undefined }
    public static func gt(_ path: String, _ value: JSONValue) -> JSONValue { .undefined }
    public static func gte(_ path: String, _ value: JSONValue) -> JSONValue { .undefined }
    public static func lt(_ path: String, _ value: JSONValue) -> JSONValue { .undefined }
    public static func lte(_ path: String, _ value: JSONValue) -> JSONValue { .undefined }
    public static func and(_ conditions: JSONValue...) -> JSONValue { .undefined }
    public static func or(_ conditions: JSONValue...) -> JSONValue { .undefined }
}
