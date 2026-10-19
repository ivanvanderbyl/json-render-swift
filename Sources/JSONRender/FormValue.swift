/// Finds form input values in action params and state.
public enum FormValue {
    /// Finds a form value, like upstream `findFormValue`. Checks, in order:
    /// a defined param named `fieldName`; the first param key ending in
    /// `.fieldName`; the first state key equal to or ending in `.fieldName`;
    /// then `fieldName` as a state path.
    public static func find(_ fieldName: String, params: JSONObject? = nil, state: JSONObject? = nil) -> JSONValue {
        if let direct = params?[fieldName], !direct.isUndefined { return direct }
        let suffix = "." + fieldName
        if let params {
            for (key, value) in params where JavaScript.endsWith(key, suffix) { return value }
        }
        if let state {
            for (key, value) in state where JavaScript.same(key, fieldName) || JavaScript.endsWith(key, suffix) {
                return value
            }
            let nested = JSONValue.object(state).value(atPath: fieldName)
            if !nested.isUndefined { return nested }
        }
        return .undefined
    }
}
