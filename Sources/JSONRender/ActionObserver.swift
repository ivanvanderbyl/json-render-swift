import Foundation

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

/// Limits observers to the task that registered them, so concurrent tests do
/// not see each other's dispatches. Observers registered outside any scope
/// see every dispatch, as upstream's registry does.
enum ActionObserverScope {
    @TaskLocal static var current: String?
}

/// The process-wide observer registry, like upstream `action-observer.ts`.
@MainActor
public enum ActionObservers {
    private static var observers: [(id: Int, scope: String?, observer: ActionObserver)] = []
    private static var nextObserverID = 0
    private static var dispatchCounter = 0

    /// Registers an observer, like upstream `registerActionObserver`. Returns
    /// a function that unregisters it.
    public static func register(_ observer: ActionObserver) -> @MainActor () -> Void {
        let id = nextObserverID
        nextObserverID += 1
        observers.append((id, ActionObserverScope.current, observer))
        return { observers.removeAll { $0.id == id } }
    }

    /// Sends a dispatch event to every observer, like upstream
    /// `notifyActionDispatch`. An observer that throws is reported and skipped.
    public static func notifyDispatch(_ info: ActionDispatchInfo) {
        for entry in observers where entry.scope == nil || entry.scope == ActionObserverScope.current {
            guard let onDispatch = entry.observer.onDispatch else { continue }
            do {
                try onDispatch(info)
            } catch {
                Diagnostics.error("[json-render] action observer threw in onDispatch: \(Actions.message(of: error).javaScriptString)")
            }
        }
    }

    /// Sends a settle event, like upstream `notifyActionSettle`.
    public static func notifySettle(_ info: ActionSettleInfo) {
        for entry in observers where entry.scope == nil || entry.scope == ActionObserverScope.current {
            guard let onSettle = entry.observer.onSettle else { continue }
            do {
                try onSettle(info)
            } catch {
                Diagnostics.error("[json-render] action observer threw in onSettle: \(Actions.message(of: error).javaScriptString)")
            }
        }
    }

    /// A unique dispatch id "<milliseconds>-<counter>", like upstream
    /// `nextActionDispatchId`.
    public static func nextDispatchID() -> String {
        dispatchCounter += 1
        return "\(Int(now()))-\(dispatchCounter)"
    }

    /// `Date.now()`: milliseconds since 1970.
    static func now() -> Double {
        (Date().timeIntervalSince1970 * 1000).rounded(.down)
    }
}
