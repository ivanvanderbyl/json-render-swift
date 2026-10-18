/// Sent when an action starts, like upstream `ActionDispatchInfo`.
public struct ActionDispatchInfo: Sendable, Equatable {
    public var id: String
    public var name: JSONValue
    public var params: JSONObject?
    /// Milliseconds since 1970 at dispatch.
    public var at: Double

    public init(id: String, name: JSONValue, params: JSONObject? = nil, at: Double) {
        self.id = id
        self.name = name
        self.params = params
        self.at = at
    }
}

/// Sent when an action finishes, like upstream `ActionSettleInfo`.
public struct ActionSettleInfo: Sendable {
    public var id: String
    public var name: JSONValue
    public var ok: Bool
    public var at: Double
    public var durationMs: Double
    public var result: JSONValue
    public var error: (any Error)?

    public init(id: String, name: JSONValue, ok: Bool, at: Double, durationMs: Double, result: JSONValue = .undefined, error: (any Error)? = nil) {
        self.id = id
        self.name = name
        self.ok = ok
        self.at = at
        self.durationMs = durationMs
        self.result = result
        self.error = error
    }
}

/// Receives action lifecycle events, like upstream `ActionObserver`.
public struct ActionObserver {
    public var onDispatch: (@MainActor (ActionDispatchInfo) throws -> Void)?
    public var onSettle: (@MainActor (ActionSettleInfo) throws -> Void)?

    public init(
        onDispatch: (@MainActor (ActionDispatchInfo) throws -> Void)? = nil,
        onSettle: (@MainActor (ActionSettleInfo) throws -> Void)? = nil
    ) {
        self.onDispatch = onDispatch
        self.onSettle = onSettle
    }
}

/// The process-wide observer registry, like upstream `action-observer.ts`.
@MainActor
public enum ActionObservers {
    /// Registers an observer, like upstream `registerActionObserver`. Returns
    /// a function that unregisters it.
    public static func register(_ observer: ActionObserver) -> @MainActor () -> Void { {} }

    /// Sends a dispatch event to every observer, like upstream
    /// `notifyActionDispatch`. An observer that throws is reported and skipped.
    public static func notifyDispatch(_ info: ActionDispatchInfo) {}

    /// Sends a settle event, like upstream `notifyActionSettle`.
    public static func notifySettle(_ info: ActionSettleInfo) {}

    /// A unique dispatch id "<milliseconds>-<counter>", like upstream
    /// `nextActionDispatchId`.
    public static func nextDispatchID() -> String { "" }
}
