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
    public static func simple(_ action: String, params: JSONObject? = nil) -> ActionBinding { ActionBinding([:]) }
    /// `actionBinding.withConfirm`.
    public static func withConfirm(_ action: String, confirm: JSONObject, params: JSONObject? = nil) -> ActionBinding { ActionBinding([:]) }
    /// `actionBinding.withSuccess`.
    public static func withSuccess(_ action: String, onSuccess: JSONObject, params: JSONObject? = nil) -> ActionBinding { ActionBinding([:]) }
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
    public var setState: @MainActor (String, JSONValue) -> Void
    public var navigate: (@MainActor (JSONValue) -> Void)?
    public var executeAction: (@MainActor (ActionBinding) async throws -> Void)?

    public init(
        action: ResolvedAction,
        handler: @escaping ActionHandler,
        setState: @escaping @MainActor (String, JSONValue) -> Void,
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
    /// message, like upstream `resolveAction`.
    public static func resolve(_ binding: ActionBinding, state: JSONValue) throws -> ResolvedAction {
        ResolvedAction(action: .undefined)
    }

    /// Replaces each `${path}` with the state value at that path, like upstream
    /// `interpolateString`.
    public static func interpolate(_ template: String, state: JSONValue) -> String { "" }

    /// Runs the handler, then `onSuccess`; on failure runs `onError` or
    /// rethrows, like upstream `executeAction`.
    @MainActor
    public static func execute(_ context: ActionExecutionContext) async throws {}

    /// The message substituted for "$error.message" in `onError.set`.
    static func message(of error: any Error) -> JSONValue { .undefined }
}
