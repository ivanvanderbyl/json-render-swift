import JSONRender
import SwiftUI

/// Draws one element type, like an upstream component render function.
///
/// The body gets the element's ``ComponentContext``. A body that throws is
/// treated like a React component that throws inside an error boundary: the
/// element draws nothing and the runtime marks it failed.
public struct Component {
    let body: @MainActor (ComponentContext) throws -> AnyView

    public init<Content: View>(@ViewBuilder _ body: @escaping @MainActor (ComponentContext) throws -> Content) {
        self.body = { AnyView(try body($0)) }
    }
}

/// Replaces the state model with what an updater returns, like upstream
/// `SetState`.
public typealias SetState = @MainActor (_ updater: (JSONObject) -> JSONObject) -> Void

/// An action implementation, like upstream `ActionFn`: it gets the action's
/// params, a state setter and the state when the action started.
public typealias ActionFunction = @MainActor (_ params: JSONObject?, _ setState: SetState, _ state: JSONObject) async throws -> Void

/// Host components and actions for a catalog, like upstream `defineRegistry`.
///
/// Create a registry once and keep it: like a new `registry` object in React,
/// a new registry makes the renderer re-render every element.
public struct Registry: ComponentLookup {
    private final class Token {}

    public let components: [String: Component]
    public let actions: [String: ActionFunction]
    /// Draws types that have no component, like upstream `fallback`.
    public let fallback: Component?
    private let catalogSlots: [String: [String]?]
    private let token = Token()

    /// - Parameters:
    ///   - catalog: The catalog the components implement. Its slot names
    ///     drive upstream's warnings about unknown slots.
    ///   - components: Component bodies by type name.
    ///   - actions: Action implementations by name; see ``handlers(for:)``.
    ///   - fallback: Draws element types without a component.
    public init(
        catalog: Catalog? = nil,
        components: [String: Component],
        actions: [String: ActionFunction] = [:],
        fallback: Component? = nil
    ) {
        self.components = components
        self.actions = actions
        self.fallback = fallback
        catalogSlots = catalog.map { catalog in catalog.components.mapValues(\.slots) } ?? [:]
    }

    /// This registry with more components, which replace components of the
    /// same name, like `{ ...registry, ...more }`.
    public func merging(_ more: [String: Component]) -> Registry {
        Registry(components: components.merging(more) { $1 }, actions: actions, fallback: fallback, catalogSlots: catalogSlots)
    }

    private init(components: [String: Component], actions: [String: ActionFunction], fallback: Component?, catalogSlots: [String: [String]?]) {
        self.components = components
        self.actions = actions
        self.fallback = fallback
        self.catalogSlots = catalogSlots
    }

    /// The component that draws a type: its own component, else the fallback.
    public func component(for type: JSONValue) -> Component? {
        components[type.javaScriptString] ?? fallback
    }

    // MARK: ComponentLookup

    public func hasComponent(_ type: String) -> Bool { components[type] != nil }
    public var hasFallback: Bool { fallback != nil }
    public func declaredSlots(for type: String) -> [String]? { catalogSlots[type] ?? nil }
    public var identity: AnyHashable { AnyHashable(ObjectIdentifier(token)) }

    // MARK: Actions

    /// Action handlers for a runtime, like upstream `handlers(getSetState,
    /// getState)`: each reads the runtime's state when it runs, and its
    /// setter replaces the runtime's state with the updater's result.
    @MainActor
    public func handlers(for runtime: Runtime) -> [String: ActionHandler] {
        handlers(
            setState: { [weak runtime] in runtime.map(Self.setter(for:)) },
            state: { [weak runtime] in runtime?.state ?? [:] }
        )
    }

    /// Action handlers with explicit state access, like upstream
    /// `handlers(getSetState, getState)`. An action does not run while
    /// `setState` returns nil.
    @MainActor
    public func handlers(
        setState: @escaping @MainActor () -> SetState?,
        state: @escaping @MainActor () -> JSONObject
    ) -> [String: ActionHandler] {
        actions.mapValues { action in
            { params in
                let setter = setState()
                let current = state()
                if let setter { try await action(params, setter, current) }
                return .undefined
            }
        }
    }

    /// Runs a named action outside a render, like upstream `executeAction`.
    /// An unknown name logs a warning.
    @MainActor
    public func executeAction(_ name: String, params: JSONObject?, setState: SetState, state: JSONObject = [:]) async throws {
        guard let action = actions[name] else {
            Diagnostics.warn("Unknown action: \(name)")
            return
        }
        try await action(params, setState, state)
    }

    /// Applies an updater's result to a runtime's state: changed top-level
    /// keys are written and removed keys become undefined.
    @MainActor
    static func setter(for runtime: Runtime) -> SetState {
        { [weak runtime] updater in
            guard let runtime else { return }
            let previous = runtime.state
            let next = updater(previous)
            var updates = JSONObject()
            for (key, value) in next.entries where !(previous[key].map { $0.strictEquals(value) } ?? false) {
                updates["/" + Self.escape(key)] = value
            }
            for key in previous.keys where !next.hasKey(key) {
                updates["/" + Self.escape(key)] = .undefined
            }
            if !updates.isEmpty { runtime.update(updates) }
        }
    }

    private static func escape(_ key: String) -> String {
        key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }
}
