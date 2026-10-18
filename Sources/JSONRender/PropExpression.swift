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
public enum PropExpression {
    /// Resolves one value, like upstream `resolvePropValue`.
    public static func resolve(_ value: JSONValue, in context: ResolutionContext) throws -> JSONValue { .undefined }

    /// Resolves every prop of an element, like upstream `resolveElementProps`.
    public static func resolveProps(_ props: JSONObject, in context: ResolutionContext) throws -> JSONObject { [:] }

    /// Maps each prop that uses `$bindState` or `$bindItem` to its absolute
    /// state path, like upstream `resolveBindings`. Returns `nil` when no prop
    /// is bound.
    public static func bindings(for props: JSONObject, in context: ResolutionContext) -> [String: String]? { nil }

    /// Resolves one action param, like upstream `resolveActionParam`:
    /// `{ "$item": "field" }` gives the field's absolute state path rather than
    /// its value, so it can be passed to `setState`.
    public static func resolveActionParam(_ value: JSONValue, in context: ResolutionContext) throws -> JSONValue { .undefined }

    /// Clears the record of unknown `$computed` names already warned about.
    static func resetWarnedComputedFunctions() {}
}
