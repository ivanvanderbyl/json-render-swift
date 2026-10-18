/// A sequence of action bindings running one after another, like upstream's
/// `for (const b of bindings) await execute(b)` loops in `emit` and in the
/// watch effect.
@MainActor
final class ActionChain {
    let bindings: [JSONValue]
    let context: ResolutionContext
    let cancellation: WatchCancellation?
    var index = 0
    var completion: ((any Error)?) -> Void

    init(bindings: [JSONValue], context: ResolutionContext, cancellation: WatchCancellation?, completion: @escaping ((any Error)?) -> Void) {
        self.bindings = bindings
        self.context = context
        self.cancellation = cancellation
        self.completion = completion
    }
}

extension Runtime {
    // MARK: Microtasks

    /// Queues work the way JavaScript queues microtasks. Renders scheduled by
    /// a state change and the continuation of an action chain run in the
    /// order they were queued, so, as upstream, a render (and its watch
    /// effects) runs before the next binding of the chain that changed state.
    func enqueue(_ job: @escaping @MainActor () -> Void) {
        microtasks.append(job)
    }

    /// Runs queued work until none is left.
    func drain() {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while !microtasks.isEmpty {
            let job = microtasks.removeFirst()
            job()
            progress += 1
        }
    }

    // MARK: Handlers

    /// Adds or replaces an action handler, like upstream `registerHandler`.
    public func registerHandler(_ name: String, _ handler: @escaping ActionHandler) {
        handlers[name] = handler
        executeVersion += 1
        contextChanged()
    }

    // MARK: Emitting events

    /// Runs the actions an element binds to an event, like upstream `emit`.
    ///
    /// Bindings run in order. Params resolve just before each binding runs,
    /// against live state, so a later binding sees what an earlier one wrote.
    /// `{ "$item": "field" }` params resolve to the item's state path. An error
    /// stops the remaining bindings and is rethrown.
    public func emit(_ event: String, nodeID: String) async throws {
        guard let instance = instances[nodeID] else { return }
        let on = try JavaScript.member("on", of: instance.element)
        let binding = on.isNullish ? JSONValue.undefined : try JavaScript.member(event, of: on)
        guard binding.isTruthy else { return }
        let bindings = binding.arrayValue?.elements ?? [binding]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let chain = ActionChain(bindings: bindings, context: instance.context, cancellation: nil) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            step(chain)
            drain()
        }
    }

    /// The handle for one event of an element, like upstream `on(event)`.
    public func eventHandle(_ event: String, nodeID: String) -> EventHandle {
        let binding = (instances[nodeID]?.element["on"] ?? .undefined)[event]
        guard binding.isTruthy else {
            return EventHandle(bound: false, shouldPreventDefault: false, emit: {})
        }
        let bindings = binding.arrayValue?.elements ?? [binding]
        return EventHandle(
            bound: true,
            shouldPreventDefault: bindings.contains { $0["preventDefault"].isTruthy },
            emit: { [weak self] in try await self?.emit(event, nodeID: nodeID) }
        )
    }

    /// Runs the next binding of a chain. Built-in actions finish at once; the
    /// chain's next step is then queued behind any render they caused.
    func step(_ chain: ActionChain) {
        if chain.cancellation?.isCancelled == true || chain.index >= chain.bindings.count {
            chain.completion(nil)
            return
        }
        let entry = chain.bindings[chain.index]
        chain.index += 1
        let binding: ActionBinding
        do {
            let params = try JavaScript.member("params", of: entry)
            if params.isTruthy {
                var live = chain.context
                live.state = .object(store.snapshot)
                var resolved = JSONObject()
                for (key, value) in try JavaScript.entries(params) {
                    resolved[key] = try PropExpression.resolveActionParam(value, in: live)
                }
                var withParams = entry.objectValue.map(JSONObject.init(copying:)) ?? JSONObject()
                withParams["params"] = .object(resolved)
                binding = ActionBinding(withParams)
            } else {
                binding = ActionBinding(entry.objectValue ?? [:])
            }
        } catch {
            chain.completion(error)
            return
        }
        perform(binding) { [weak self] error in
            if let error {
                chain.completion(error)
                return
            }
            self?.enqueue { self?.step(chain) }
        }
    }

    // MARK: Executing actions (upstream ActionProvider.execute)

    /// Executes an action binding, like upstream `useActions().execute`.
    ///
    /// Built-in actions are handled here: `setState`, `pushState`,
    /// `removeState`, `push`, `pop` and `validateForm`. Anything else runs its
    /// registered handler, after confirmation when the binding has `confirm`,
    /// followed by `onSuccess` or `onError`. Observers see every dispatch.
    public func execute(_ binding: ActionBinding) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            perform(binding) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            drain()
        }
    }

    /// Executes one binding and calls `completion` when it settles: at once
    /// for built-in actions, and after the handler, confirmation and
    /// `onSuccess` / `onError` otherwise.
    func perform(_ binding: ActionBinding, completion: @escaping ((any Error)?) -> Void) {
        let resolved: ResolvedAction
        do {
            resolved = try Actions.resolve(binding, state: .object(store.snapshot))
        } catch {
            completion(error)
            return
        }
        let dispatchID = ActionObservers.nextDispatchID()
        let dispatchedAt = ActionObservers.now()
        ActionObservers.notifyDispatch(ActionDispatchInfo(id: dispatchID, name: resolved.action, params: resolved.params, at: dispatchedAt))
        let settle = { (error: (any Error)?) in
            let now = ActionObservers.now()
            ActionObservers.notifySettle(ActionSettleInfo(
                id: dispatchID, name: resolved.action, ok: error == nil, at: now, durationMs: now - dispatchedAt, error: error
            ))
        }

        do {
            if try performBuiltIn(resolved.action, params: resolved.params) {
                settle(nil)
                completion(nil)
                return
            }
        } catch {
            settle(error)
            completion(error)
            return
        }
        guard let handler = handlers[resolved.action.javaScriptString] else {
            Diagnostics.warn("No handler registered for action: \(resolved.action.javaScriptString)")
            settle(nil)
            completion(nil)
            return
        }
        if resolved.confirm.isTruthy {
            // Upstream reports the dispatch settled as soon as it starts
            // waiting for confirmation.
            settle(nil)
            pendingConfirmation = PendingConfirmation(action: resolved)
            confirmation = { [weak self] confirmed in
                guard let self else { return }
                guard confirmed else {
                    completion(JavaScriptError.error("Action cancelled"))
                    return
                }
                self.runHandler(handler, for: resolved) { error in completion(error) }
            }
            contextChanged()
            return
        }
        runHandler(handler, for: resolved) { error in
            settle(error)
            completion(error)
        }
    }

    /// Runs a handler with `onSuccess` and `onError`, marking the action
    /// loading while it runs.
    private func runHandler(_ handler: @escaping ActionHandler, for resolved: ResolvedAction, completion: @escaping ((any Error)?) -> Void) {
        let name = resolved.action.javaScriptString
        loadingActions.insert(name)
        contextChanged()
        let context = ActionExecutionContext(
            action: resolved,
            handler: handler,
            setState: { [unowned self] path, value in self.set(path, value) },
            navigate: navigate,
            executeAction: { [unowned self] binding in try await self.execute(binding) }
        )
        activeTasks += 1
        let work: @MainActor () async -> Void = { [weak self] in
            var failure: (any Error)?
            do {
                try await Actions.execute(context)
            } catch {
                failure = error
            }
            guard let self else { return }
            self.activeTasks -= 1
            self.enqueue {
                self.loadingActions.remove(name)
                self.contextChanged()
                completion(failure)
            }
            if self.operationDepth == 0 { self.drain() }
        }
        // Upstream calls the handler synchronously when the action runs.
        // `Task.immediate` does the same, running the handler until it first
        // suspends; earlier systems start it on the next main-actor turn.
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
            Task.immediate { @MainActor in await work() }
        } else {
            Task { @MainActor in await work() }
        }
    }

    /// Runs the action waiting for confirmation, like upstream `confirm`.
    public func confirm() {
        resolveConfirmation(true)
    }

    /// Cancels the action waiting for confirmation, like upstream `cancel`.
    /// Its `execute` throws "Action cancelled".
    public func cancel() {
        resolveConfirmation(false)
    }

    private func resolveConfirmation(_ confirmed: Bool) {
        guard let resume = confirmation else { return }
        confirmation = nil
        pendingConfirmation = nil
        contextChanged()
        enqueue { resume(confirmed) }
        drain()
    }

    // MARK: Built-in actions

    /// Performs a built-in action. Returns false for other names.
    private func performBuiltIn(_ name: JSONValue, params: JSONObject) throws -> Bool {
        guard case let .string(action) = name else { return false }
        let get = { [unowned self] (path: String) in self.store.get(path) }
        switch action {
        case "setState":
            let statePath = params["statePath"] ?? .undefined
            if statePath.isTruthy { set(try path(statePath), params["value"] ?? .undefined) }
            return true
        case "pushState":
            let statePath = params["statePath"] ?? .undefined
            if statePath.isTruthy {
                let path = try path(statePath)
                let value = deepResolve(params["value"] ?? .undefined, get: get)
                var items = try spread(get(path), name: "arr")
                items.append(value)
                set(path, .array(JSONArray(items)))
                let clear = params["clearStatePath"] ?? .undefined
                if clear.isTruthy { set(try self.path(clear), "") }
            }
            return true
        case "removeState":
            let statePath = params["statePath"] ?? .undefined
            let index = params["index"] ?? .undefined
            if !statePath.isUndefined, !index.isUndefined {
                let path = try path(statePath)
                switch get(path) {
                case .undefined, .null:
                    set(path, [])
                case let .array(array):
                    set(path, .array(JSONArray(array.enumerated().filter { !JSONValue.number(Double($0.offset)).strictEquals(index) }.map(\.element))))
                default:
                    throw JavaScriptError.typeError("arr.filter is not a function")
                }
            }
            return true
        case "push":
            let screen = params["screen"] ?? .undefined
            if screen.isTruthy {
                let current = get("/currentScreen")
                var stack = try spread(get("/navStack"), name: "navStack")
                stack.append(current.isTruthy ? current : "")
                set("/navStack", .array(JSONArray(stack)))
                set("/currentScreen", screen)
            }
            return true
        case "pop":
            // `navStack.length > 0`, `navStack.slice(0, -1)`, `navStack[length - 1]`.
            var previous: JSONValue?
            switch get("/navStack") {
            case let .array(stack) where !stack.isEmpty:
                previous = stack.last
                set("/navStack", .array(JSONArray(stack.dropLast())))
            case let .string(stack) where !stack.utf16.isEmpty:
                let units = Array(stack.utf16)
                previous = .string(String(decoding: [units.last!], as: UTF16.self))
                set("/navStack", .string(String(decoding: units.dropLast(), as: UTF16.self)))
            default:
                break
            }
            if let previous { set("/currentScreen", previous.isTruthy ? previous : .undefined) }
            return true
        case "validateForm":
            let valid = try validation.validateAll()
            var errors = JSONObject()
            for (path, field) in validation.fieldStates {
                if let result = field.result, !result.valid { errors[path] = .array(JSONArray(result.errors)) }
            }
            let statePath = params["statePath"] ?? .undefined
            set(statePath.isTruthy ? try path(statePath) : "/formValidation", ["valid": .bool(valid), "errors": .object(errors)])
            return true
        default:
            return false
        }
    }

    /// A state path from an action param. Upstream passes the value straight
    /// to `set`, which fails on non-strings.
    private func path(_ value: JSONValue) throws -> String {
        guard case let .string(path) = value else { throw JavaScriptError.typeError("path.startsWith is not a function") }
        return path
    }

    /// `[...value]` for a state value, with `?? []` for null and undefined.
    private func spread(_ value: JSONValue, name: String) throws -> [JSONValue] {
        switch value {
        case .undefined, .null: return []
        case let .array(array): return array.elements
        case let .string(string): return string.unicodeScalars.map { .string(String($0)) }
        default: throw JavaScriptError.typeError("\(name) is not iterable")
        }
    }

    /// Upstream `deepResolveValue` for `pushState` values: `{ "$state": path }`
    /// reads state, and `"$id"` or `{ "$id": true }` generate a unique id.
    private func deepResolve(_ value: JSONValue, get: (String) -> JSONValue) -> JSONValue {
        switch value {
        case .string("$id"):
            return .string(UniqueID.next())
        case let .object(object):
            if object.count == 1, case let .string(path)? = object["$state"] { return get(path) }
            if object.count == 1, object.hasKey("$id") { return .string(UniqueID.next()) }
            var resolved = JSONObject()
            for (key, member) in object { resolved[key] = deepResolve(member, get: get) }
            return .object(resolved)
        case let .array(array):
            return .array(JSONArray(array.map { deepResolve($0, get: get) }))
        default:
            return value
        }
    }
}

/// Ids for `"$id"` in `pushState`: "<milliseconds>-<counter>", like upstream.
@MainActor
enum UniqueID {
    private static var counter = 0

    static func next() -> String {
        counter += 1
        return "\(Int(ActionObservers.now()))-\(counter)"
    }
}
