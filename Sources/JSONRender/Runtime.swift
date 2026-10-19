import Observation

/// A state change reported to `onStateChange`.
public struct StateChange: Sendable, Equatable {
    public var path: String
    public var value: JSONValue

    public init(path: String, value: JSONValue) {
        self.path = path
        self.value = value
    }
}

/// A path's value and a setter, like upstream `useStateBinding`.
public struct StateBinding {
    public var value: JSONValue
    public var set: (JSONValue) -> Void
}

/// An action waiting for the user to confirm, like upstream `PendingConfirmation`.
public struct PendingConfirmation: Sendable {
    /// The resolved action, with `confirm` holding the dialog's title, message,
    /// labels and variant.
    public var action: ResolvedAction
}

/// What a component gets for one of its events, like upstream `EventHandle`.
public struct EventHandle {
    /// True when the element binds an action to the event.
    public var bound: Bool
    /// True when any binding sets `preventDefault`.
    public var shouldPreventDefault: Bool
    /// Runs the bound actions and waits for them.
    public var emit: @MainActor () async throws -> Void
    /// Starts the bound actions without waiting, like upstream's `emit()`.
    public var fire: @MainActor () -> Void
}

/// Everything a rendered spec needs, like upstream `JSONUIProvider` together
/// with a `Renderer`: the state model, action handlers, form validation,
/// `$computed` functions and directives, and the render tree.
///
/// ``render(_:components:loading:)`` builds the tree the SwiftUI renderer
/// draws. State changes re-render on the next main-actor turn, and element
/// `watch` bindings fire after each render, as upstream's effects do.
@MainActor
@Observable
public final class Runtime {
    // MARK: Configuration

    /// Functions for `$computed` expressions. Changing them re-renders.
    public var functions: [String: ComputedFunction] {
        get { storedFunctions }
        set {
            storedFunctions = newValue
            functionsVersion += 1
            contextChanged()
        }
    }

    /// Custom directives. Changing them re-renders.
    public var directives: [DirectiveDefinition] {
        get { storedDirectives }
        set {
            storedDirectives = newValue
            directiveRegistry = newValue.isEmpty ? nil : DirectiveRegistry(newValue)
            directivesVersion += 1
            contextChanged()
        }
    }

    @ObservationIgnored var storedFunctions: [String: ComputedFunction]
    @ObservationIgnored var storedDirectives: [DirectiveDefinition]

    /// Navigation for `onSuccess.navigate`, like upstream `navigate`.
    @ObservationIgnored public var navigate: (@MainActor (JSONValue) -> Void)?

    /// Form validation for components with checks.
    public let validation: FormValidation

    // MARK: Render output

    /// The rendered tree, or nil when there is no spec, no root or no root element.
    public internal(set) var tree: RenderNode?
    /// An error that escaped every error boundary, which makes upstream drop
    /// the whole render.
    public internal(set) var renderError: String?
    /// Whether the spec is still streaming.
    public internal(set) var loading = false
    /// The state model.
    public internal(set) var state: JSONObject
    /// An action waiting for ``confirm()`` or ``cancel()``.
    public internal(set) var pendingConfirmation: PendingConfirmation?
    /// Names of actions whose handlers are running.
    public internal(set) var loadingActions: Set<String> = []

    // MARK: Internals

    @ObservationIgnored let store: any StateStore
    @ObservationIgnored let isControlled: Bool
    @ObservationIgnored var onStateChange: (@MainActor ([StateChange]) -> Void)?
    @ObservationIgnored var handlers: [String: ActionHandler]
    @ObservationIgnored var directiveRegistry: DirectiveRegistry?
    @ObservationIgnored var initialState: JSONObject
    @ObservationIgnored var unsubscribe: (@MainActor () -> Void)?

    @ObservationIgnored var spec: Spec?
    @ObservationIgnored var components: (any ComponentLookup)?
    @ObservationIgnored var signatures = ElementSignatures()
    @ObservationIgnored var contextEpoch = 0
    @ObservationIgnored var componentsEpoch = 0
    @ObservationIgnored var instances: [String: ElementInstance] = [:]
    @ObservationIgnored var boundaryErrors: [String: Int] = [:]
    @ObservationIgnored var componentFailures: [String: Int] = [:]
    @ObservationIgnored var renderScheduled = false
    @ObservationIgnored var progress = 0
    @ObservationIgnored var confirmation: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var microtasks: [@MainActor () -> Void] = []
    @ObservationIgnored var isDraining = false
    @ObservationIgnored var activeTasks = 0
    @ObservationIgnored var operationDepth = 0
    @ObservationIgnored var forcedRenders: Set<String> = []
    /// Versions of the inputs a watch effect depends on (upstream's effect
    /// dependencies): state, functions, directives and `execute`.
    @ObservationIgnored var stateVersion = 0
    @ObservationIgnored var functionsVersion = 0
    @ObservationIgnored var directivesVersion = 0
    @ObservationIgnored var executeVersion = 0
    @ObservationIgnored var watchStates: [String: WatchState] = [:]
    @ObservationIgnored var lastMountOrder: [String] = []
    @ObservationIgnored var scopeTokenCounter = 0
    @ObservationIgnored var componentsIdentity: AnyHashable?

    public init(
        store: (any StateStore)? = nil,
        initialState: JSONObject = [:],
        handlers: [String: ActionHandler] = [:],
        navigate: (@MainActor (JSONValue) -> Void)? = nil,
        validationFunctions: [String: ValidationFunction] = [:],
        functions: [String: ComputedFunction] = [:],
        directives: [DirectiveDefinition] = [],
        onStateChange: (@MainActor ([StateChange]) -> Void)? = nil
    ) {
        let backing = store ?? MemoryStateStore(initialState)
        self.store = backing
        isControlled = store != nil
        self.initialState = initialState
        self.handlers = handlers
        self.navigate = navigate
        storedFunctions = functions
        storedDirectives = directives
        directiveRegistry = directives.isEmpty ? nil : DirectiveRegistry(directives)
        self.onStateChange = onStateChange
        state = backing.snapshot
        validation = FormValidation(customFunctions: validationFunctions)
        validation.currentState = { [unowned self] in self.store.snapshot }
        validation.onChange = { [unowned self] in
            // The validation context feeds upstream's `execute`.
            self.executeVersion += 1
            self.contextChanged()
        }
        unsubscribe = backing.subscribe { [weak self] in self?.storeChanged() }
    }

    // MARK: State (upstream StateProvider)

    /// Reads a state path, like upstream `useStateStore().get`.
    public func get(_ path: String) -> JSONValue { store.get(path) }

    /// Writes a state path, like upstream `useStateStore().set`. Reports the
    /// change to `onStateChange` when the store is not external.
    public func set(_ path: String, _ value: JSONValue) {
        let previous = store.snapshot
        operation {
            store.set(path, value)
            if !isControlled, !store.snapshot.isIdentical(to: previous) {
                onStateChange?([StateChange(path: path, value: value)])
            }
        }
    }

    /// Runs a state operation, then any render it scheduled. Upstream
    /// renders after `set` returns, so `onStateChange` comes first.
    func operation(_ body: () -> Void) {
        operationDepth += 1
        body()
        operationDepth -= 1
        if operationDepth == 0 { drain() }
    }

    /// Writes several paths at once, like upstream `useStateStore().update`.
    public func update(_ updates: JSONObject) {
        let previous = store.snapshot
        operation {
            store.update(updates)
            if !isControlled, !store.snapshot.isIdentical(to: previous) {
                let changes = updates.filter { !JSONValue.object(previous).value(atPath: $0.key).strictEquals($0.value) }
                    .map { StateChange(path: $0.key, value: $0.value) }
                if !changes.isEmpty { onStateChange?(changes) }
            }
        }
    }

    /// A value and setter for a path, like upstream `useStateBinding`.
    public func binding(_ path: String) -> StateBinding {
        StateBinding(value: get(path), set: { [weak self] value in self?.set(path, value) })
    }

    /// Applies a new initial state, like upstream StateProvider when its
    /// `initialState` prop changes: the difference between the old and new
    /// flattened state is written to the store, without `onStateChange`.
    public func setInitialState(_ newState: JSONObject) {
        guard !isControlled, !newState.isIdentical(to: initialState) else { return }
        let previousFlat = initialState.isEmpty ? JSONObject() : JSONPointer.flatten(initialState)
        let nextFlat = newState.isEmpty ? JSONObject() : JSONPointer.flatten(newState)
        initialState = newState
        var updates = JSONObject()
        for key in previousFlat.keys + nextFlat.keys where updates[key] == nil {
            let before = previousFlat[key] ?? .undefined
            let after = nextFlat[key] ?? .undefined
            if !before.strictEquals(after) || previousFlat.hasKey(key) != nextFlat.hasKey(key) {
                updates[key] = nextFlat.hasKey(key) ? after : .undefined
            }
        }
        if !updates.isEmpty { operation { store.update(updates) } }
    }

    /// The visibility context, like upstream `useVisibility().ctx`.
    public var visibilityContext: ResolutionContext { ResolutionContext(state: .object(state)) }

    /// Evaluates a condition against the state, like upstream `useIsVisible`.
    /// A malformed condition is reported and treated as hidden.
    public func isVisible(_ condition: JSONValue) -> Bool {
        do {
            return try Visibility.evaluate(condition, in: visibilityContext)
        } catch {
            Diagnostics.error(Actions.message(of: error).javaScriptString)
            return false
        }
    }

    private func storeChanged() {
        state = store.snapshot
        stateVersion += 1
        contextChanged()
    }

    /// Any provider value changed, so every mounted element re-renders.
    func contextChanged() {
        contextEpoch += 1
        scheduleRender()
    }

    func scheduleRender() {
        guard spec != nil else { return }
        if !renderScheduled {
            renderScheduled = true
            enqueue { [weak self] in
                guard let self, self.renderScheduled else { return }
                self.renderNow()
            }
        }
        if operationDepth == 0 { drain() }
    }

    // MARK: Settling

    /// Waits until scheduled renders and action handlers have finished, like
    /// React's `act`. Handlers blocked on outside work are left running.
    public func settle() async {
        var idleTurns = 0
        for _ in 0..<1000 {
            drain()
            let before = progress
            await Task.yield()
            if progress == before, microtasks.isEmpty {
                idleTurns += 1
                if idleTurns >= 3 { return }
            } else {
                idleTurns = 0
            }
        }
    }
}
