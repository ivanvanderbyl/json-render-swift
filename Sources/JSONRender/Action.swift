import Foundation

/// An action binding: the value of an `on` or `watch` entry, like upstream
/// `ActionBinding`: `{ "action": name, "params": {...}, "confirm": {...},
/// "onSuccess": {...}, "onError": {...}, "preventDefault": bool }`.
public struct ActionBinding: Sendable, Equatable {
    public var object: JSONObject

    public init(_ object: JSONObject) { self.object = object }

    public init(action: String, params: JSONObject? = nil) {
        object = ["action": .string(action)]
        if let params { object["params"] = .object(params) }
    }

    public var action: JSONValue { object["action"] ?? .undefined }
    public var params: JSONValue { object["params"] ?? .undefined }
    public var confirm: JSONValue { object["confirm"] ?? .undefined }
    public var onSuccess: JSONValue { object["onSuccess"] ?? .undefined }
    public var onError: JSONValue { object["onError"] ?? .undefined }
    public var preventDefault: JSONValue { object["preventDefault"] ?? .undefined }

    // MARK: Builders (upstream `actionBinding`)

    /// `actionBinding.simple`.
    public static func simple(_ action: String, params: JSONObject? = nil) -> ActionBinding {
        ActionBinding(["action": .string(action), "params": params.map(JSONValue.object) ?? .undefined])
    }

    /// `actionBinding.withConfirm`.
    public static func withConfirm(_ action: String, confirm: JSONObject, params: JSONObject? = nil) -> ActionBinding {
        ActionBinding([
            "action": .string(action), "params": params.map(JSONValue.object) ?? .undefined, "confirm": .object(confirm),
        ])
    }

    /// `actionBinding.withSuccess`.
    public static func withSuccess(_ action: String, onSuccess: JSONObject, params: JSONObject? = nil) -> ActionBinding {
        ActionBinding([
            "action": .string(action), "params": params.map(JSONValue.object) ?? .undefined, "onSuccess": .object(onSuccess),
        ])
    }
}

/// An action binding with its dynamic params resolved, like upstream `ResolvedAction`.
public struct ResolvedAction: Sendable, Equatable {
    public var action: JSONValue
    public var params: JSONObject
    public var confirm: JSONValue
    public var onSuccess: JSONValue
    public var onError: JSONValue

    public init(action: JSONValue, params: JSONObject = [:], confirm: JSONValue = .undefined, onSuccess: JSONValue = .undefined, onError: JSONValue = .undefined) {
        self.action = action
        self.params = params
        self.confirm = confirm
        self.onSuccess = onSuccess
        self.onError = onError
    }
}

/// Runs an action: receives resolved params and returns a result.
public typealias ActionHandler = @MainActor (JSONObject) async throws -> JSONValue

/// What ``Actions/execute(_:)`` needs, like upstream `ActionExecutionContext`.
public struct ActionExecutionContext {
    public var action: ResolvedAction
    public var handler: ActionHandler
    public var setState: @MainActor (String, JSONValue) throws -> Void
    public var navigate: (@MainActor (JSONValue) -> Void)?
    public var executeAction: (@MainActor (ActionBinding) async throws -> Void)?

    public init(
        action: ResolvedAction,
        handler: @escaping ActionHandler,
        setState: @escaping @MainActor (String, JSONValue) throws -> Void,
        navigate: (@MainActor (JSONValue) -> Void)? = nil,
        executeAction: (@MainActor (ActionBinding) async throws -> Void)? = nil
    ) {
        self.action = action
        self.handler = handler
        self.setState = setState
        self.navigate = navigate
        self.executeAction = executeAction
    }
}

/// Action resolution and execution, like upstream `actions.ts`.
public enum Actions {
    /// Resolves `$state` params and interpolates the confirm title and
    /// message, like upstream `resolveAction`. Params are resolved one level
    /// deep with ``DynamicValue/resolve(_:state:)``.
    public static func resolve(_ binding: ActionBinding, state: JSONValue) throws -> ResolvedAction {
        var params = JSONObject()
        if binding.params.isTruthy {
            for (key, value) in try JavaScript.entries(binding.params) {
                params[key] = try DynamicValue.resolve(value, state: state)
            }
        }
        var confirm = binding.confirm
        if confirm.isTruthy {
            var interpolated = confirm.objectValue.map(JSONObject.init(copying:)) ?? JSONObject()
            interpolated["message"] = .string(try interpolate(member: "message", of: confirm, state: state))
            interpolated["title"] = .string(try interpolate(member: "title", of: confirm, state: state))
            confirm = .object(interpolated)
        }
        return ResolvedAction(
            action: binding.action,
            params: params,
            confirm: confirm,
            onSuccess: binding.onSuccess,
            onError: binding.onError
        )
    }

    /// `interpolateString(confirm.member, state)`, which throws when the member
    /// is not a string.
    private static func interpolate(member: String, of confirm: JSONValue, state: JSONValue) throws -> String {
        let template = try JavaScript.member(member, of: confirm)
        guard case let .string(text) = template else {
            if template.isNullish {
                throw JavaScriptError.typeError("Cannot read properties of \(template.javaScriptString) (reading 'replace')")
            }
            throw JavaScriptError.typeError("template.replace is not a function")
        }
        return interpolate(text, state: state)
    }

    /// Replaces each `${path}` with the state value at that path, like upstream
    /// `interpolateString`. Missing, `null` and `undefined` values become "".
    public static func interpolate(_ template: String, state: JSONValue) -> String {
        JavaScript.replacePlaceholders(in: template) { path in
            let value = state.value(atPath: path)
            return value.isNullish ? "" : value.javaScriptString
        }
    }

    /// Runs the handler, then `onSuccess`; on failure runs `onError` or
    /// rethrows, like upstream `executeAction`.
    ///
    /// `onSuccess` is `{ "navigate": path }`, `{ "set": { path: value } }` or
    /// `{ "action": name, "params": {...} }`. `onError` is `set` or `action`;
    /// in `set`, the string "$error.message" becomes the error's message. As
    /// upstream, an error thrown while handling `onSuccess` also runs `onError`.
    @MainActor
    public static func execute(_ context: ActionExecutionContext) async throws {
        let action = context.action
        do {
            _ = try await context.handler(action.params)
            if action.onSuccess.isTruthy {
                let onSuccess = action.onSuccess
                if try has("navigate", onSuccess), let navigate = context.navigate {
                    navigate(onSuccess["navigate"])
                } else if try has("set", onSuccess) {
                    for (path, value) in try JavaScript.entries(onSuccess["set"]) {
                        try context.setState(path, value)
                    }
                } else if try has("action", onSuccess), let executeAction = context.executeAction {
                    try await executeAction(ActionBinding(onSuccess.objectValue ?? [:]))
                }
            }
        } catch {
            guard action.onError.isTruthy else { throw error }
            let onError = action.onError
            if try has("set", onError) {
                for (path, value) in try JavaScript.entries(onError["set"]) {
                    try context.setState(path, value == "$error.message" ? message(of: error) : value)
                }
            } else if try has("action", onError), let executeAction = context.executeAction {
                try await executeAction(ActionBinding(onError.objectValue ?? [:]))
            }
        }
    }

    /// `key in value` for an onSuccess or onError handler object.
    private static func has(_ key: String, _ value: JSONValue) throws -> Bool {
        switch value {
        case let .object(object): return object.hasKey(key)
        case .array: return false
        default:
            throw JavaScriptError.typeError("Cannot use 'in' operator to search for '\(key)' in \(value.javaScriptString)")
        }
    }

    /// The message substituted for "$error.message" in `onError.set`: the
    /// message of a ``JavaScriptError``, the description of a
    /// `LocalizedError`, or the error's description.
    static func message(of error: any Error) -> JSONValue {
        if let error = error as? JavaScriptError { return .string(error.message) }
        if let description = (error as? any LocalizedError)?.errorDescription { return .string(description) }
        return .string(String(describing: error))
    }
}
