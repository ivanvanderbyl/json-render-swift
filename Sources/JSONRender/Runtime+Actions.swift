extension Runtime {
    // MARK: Handlers

    /// Adds or replaces an action handler, like upstream `registerHandler`.
    public func registerHandler(_ name: String, _ handler: @escaping ActionHandler) {
        handlers[name] = handler
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
        try await runBindings(on.isNullish ? .undefined : try JavaScript.member(event, of: on), context: instance.context)
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

    /// Runs one `on` or `watch` entry: a binding or an array of bindings.
    func runBindings(_ binding: JSONValue, context: ResolutionContext, isCancelled: @MainActor () -> Bool = { false }) async throws {
        guard binding.isTruthy else { return }
        let bindings = binding.arrayValue?.elements ?? [binding]
        for entry in bindings {
            if isCancelled() { return }
            let params = try JavaScript.member("params", of: entry)
            guard params.isTruthy else {
                try await execute(ActionBinding(entry.objectValue ?? [:]))
                continue
            }
            var live = context
            live.state = .object(store.snapshot)
            var resolved = JSONObject()
            for (key, value) in try JavaScript.entries(params) {
                resolved[key] = try PropExpression.resolveActionParam(value, in: live)
            }
            var withParams = entry.objectValue.map(JSONObject.init(copying:)) ?? JSONObject()
            withParams["params"] = .object(resolved)
            try await execute(ActionBinding(withParams))
            progress += 1
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
        let resolved = try Actions.resolve(binding, state: .object(store.snapshot))
        let dispatchID = ActionObservers.nextDispatchID()
        let dispatchedAt = ActionObservers.now()
        ActionObservers.notifyDispatch(ActionDispatchInfo(id: dispatchID, name: resolved.action, params: resolved.params, at: dispatchedAt))
        func settle(ok: Bool, error: (any Error)?) {
            let now = ActionObservers.now()
            ActionObservers.notifySettle(ActionSettleInfo(
                id: dispatchID, name: resolved.action, ok: ok, at: now, durationMs: now - dispatchedAt, error: error
            ))
        }

        let name = resolved.action
        let params = resolved.params
        do {
            if try performBuiltIn(name, params: params) {
                settle(ok: true, error: nil)
                return
            }
            guard let handler = handlers[name.javaScriptString] else {
                Diagnostics.warn("No handler registered for action: \(name.javaScriptString)")
                settle(ok: true, error: nil)
                return
            }
            if resolved.confirm.isTruthy {
                // Upstream reports the dispatch settled as soon as it starts
                // waiting for confirmation.
                settle(ok: true, error: nil)
                try await waitForConfirmation(resolved)
                try await runHandler(handler, for: resolved)
                return
            }
            try await runHandler(handler, for: resolved)
            settle(ok: true, error: nil)
        } catch {
            settle(ok: false, error: error)
            throw error
        }
    }

    private func runHandler(_ handler: @escaping ActionHandler, for resolved: ResolvedAction) async throws {
        let name = resolved.action.javaScriptString
        loadingActions.insert(name)
        contextChanged()
        defer {
            loadingActions.remove(name)
            contextChanged()
        }
        try await Actions.execute(ActionExecutionContext(
            action: resolved,
            handler: handler,
            setState: { [unowned self] path, value in self.set(path, value) },
            navigate: navigate,
            executeAction: { [unowned self] binding in try await self.execute(binding) }
        ))
    }

    private func waitForConfirmation(_ resolved: ResolvedAction) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            confirmation = continuation
            pendingConfirmation = PendingConfirmation(action: resolved)
            contextChanged()
        }
    }

    /// Runs the action waiting for confirmation, like upstream `confirm`.
    public func confirm() {
        guard let continuation = confirmation else { return }
        confirmation = nil
        pendingConfirmation = nil
        contextChanged()
        continuation.resume()
    }

    /// Cancels the action waiting for confirmation, like upstream `cancel`.
    /// Its `execute` throws "Action cancelled".
    public func cancel() {
        guard let continuation = confirmation else { return }
        confirmation = nil
        pendingConfirmation = nil
        contextChanged()
        continuation.resume(throwing: JavaScriptError.error("Action cancelled"))
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
                let current = get(path)
                switch current {
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
