/// The scope of one item rendered by an element's `repeat` field.
public enum RepeatScope {
    /// Resolves a repeat `statePath`, like upstream `resolveRepeatStatePath`.
    /// A string is returned unchanged. `{ "$item": "field" }` resolves against
    /// the enclosing item's path, and is `nil` outside a repeat scope.
    public static func resolveStatePath(_ statePath: JSONValue, base: String? = nil) throws -> String? {
        if case let .string(path) = statePath { return path }
        guard let base else { return nil }
        let item: JSONValue
        switch statePath {
        case .undefined, .null:
            throw JavaScriptError.typeError("Cannot read properties of \(statePath.javaScriptString) (reading '$item')")
        case let .object(object):
            item = object["$item"] ?? .undefined
        default:
            item = .undefined
        }
        if item == "" || item == "/" { return base }
        guard case let .string(child) = item else {
            if item.isNullish {
                throw JavaScriptError.typeError("Cannot read properties of \(item.javaScriptString) (reading 'startsWith')")
            }
            throw JavaScriptError.typeError("childPath.startsWith is not a function")
        }
        return join(base, child)
    }

    /// The state path of one item, like upstream `resolveRepeatItemStatePath`.
    public static func itemStatePath(_ statePath: String, index: Int) -> String {
        join(statePath, String(index))
    }

    private static func join(_ base: String, _ childPath: String) -> String {
        let child = JavaScript.startsWith(childPath, "/") ? JavaScript.dropFirstUnit(childPath) : childPath
        if base.isEmpty || base == "/" { return "/" + child }
        return base + "/" + child
    }
}
