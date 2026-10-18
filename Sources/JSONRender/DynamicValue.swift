/// A literal or a `{ "$state": "/path" }` reference, used in action params and
/// validation args.
public enum DynamicValue {
    /// Resolves a dynamic value against the state model, like upstream
    /// `resolveDynamicValue`: `null` and `undefined` give `undefined`, an
    /// object with a `$state` member reads that path, and anything else is
    /// returned unchanged.
    public static func resolve(_ value: JSONValue, state: JSONValue) throws -> JSONValue {
        switch value {
        case .undefined, .null:
            return .undefined
        case let .object(object):
            guard let path = object["$state"] else { return value }
            return try readState(state, path: path)
        default:
            return value
        }
    }

    /// `getByPath(state, path)` where `path` is whatever the spec supplied.
    static func readState(_ state: JSONValue, path: JSONValue) throws -> JSONValue {
        guard let path = try JSONPointer.path(from: path) else { return state }
        return state.value(atPath: path)
    }
}
