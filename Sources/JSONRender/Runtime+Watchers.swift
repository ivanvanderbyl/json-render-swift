/// The state of one element's `watch` effect, like the refs upstream keeps in
/// `ReactiveElementRenderer`.
struct WatchState {
    /// The watched values the last effect run saw; nil before the first run.
    var previousValues: [(path: String, value: JSONValue)]?
    /// The dependencies and config the effect last ran with.
    var effectKey: [Int]
    var config: JSONValue
    /// Cancels the action chain the last effect run started.
    var cancellation: WatchCancellation?
}

/// Set when an effect re-runs or its element unmounts, so a running watch
/// action chain stops before its next binding, as upstream's cleanup does.
@MainActor
final class WatchCancellation {
    var isCancelled = false
}

extension Runtime {
    /// Upstream's watch `useEffect`: after each render, for every mounted
    /// element with a `watch` field (children before parents), compares the
    /// watched paths with the previous run and fires the bindings of paths
    /// whose value changed (`!==`). The first run after mounting only records
    /// values. A new run cancels the previous run's chain; unmounting cancels
    /// it too.
    func runWatchEffects(order: [String], previous: [String: ElementInstance]) {
        for id in watchStates.keys where instances[id] == nil {
            watchStates[id]?.cancellation?.isCancelled = true
            watchStates[id] = nil
        }
        lastMountOrder = order
        for id in order {
            guard let instance = instances[id] else { continue }
            let config = instance.element["watch"]
            guard case let .object(watch) = config, !watch.isEmpty else {
                if let state = watchStates[id] {
                    state.cancellation?.isCancelled = true
                    watchStates[id] = nil
                }
                continue
            }
            // The effect re-runs only when one of its dependencies changed.
            if let state = watchStates[id], state.effectKey == instance.effectKey, state.config.strictEquals(config) { continue }

            let values = watch.keys.map { (path: $0, value: JSONValue.object(state).value(atPath: $0)) }
            var watchState = watchStates[id] ?? WatchState(previousValues: nil, effectKey: instance.effectKey, config: config)
            watchState.cancellation?.isCancelled = true
            let prior = watchState.previousValues
            watchState.previousValues = values
            watchState.effectKey = instance.effectKey
            watchState.config = config
            guard let prior else {
                watchState.cancellation = nil
                watchStates[id] = watchState
                continue
            }
            let changed = values.filter { current in
                !(prior.first { $0.path == current.path }?.value ?? .undefined).strictEquals(current.value)
            }
            guard !changed.isEmpty else {
                watchState.cancellation = nil
                watchStates[id] = watchState
                continue
            }
            let cancellation = WatchCancellation()
            watchState.cancellation = cancellation
            watchStates[id] = watchState
            // Upstream starts the chain inside the effect, so its first binding
            // runs now and later ones after any render it causes.
            let bindings = changed.flatMap { change -> [JSONValue] in
                let binding = watch[change.path] ?? .undefined
                guard binding.isTruthy else { return [] }
                return binding.arrayValue?.elements ?? [binding]
            }
            let chain = ActionChain(bindings: bindings, context: instance.context, cancellation: cancellation) { error in
                if let error { Diagnostics.error(Actions.message(of: error).javaScriptString) }
            }
            step(chain)
        }
    }
}
