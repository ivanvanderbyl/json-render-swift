/// The state of one element's `watch` effect, like the refs upstream keeps in
/// `ReactiveElementRenderer`.
struct WatchState {
    /// The watched values the last effect run saw; nil before the first run.
    var previousValues: [(path: String, value: JSONValue)]?
    /// The context and config the effect last ran with.
    var epoch: Int
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
            // A memoised element did not re-render, so its effect does not re-run.
            if let state = watchStates[id], state.epoch == instance.epoch, state.config.strictEquals(config) { continue }

            let values = watch.keys.map { (path: $0, value: JSONValue.object(state).value(atPath: $0)) }
            var watchState = watchStates[id] ?? WatchState(previousValues: nil, epoch: instance.epoch, config: config)
            watchState.cancellation?.isCancelled = true
            let prior = watchState.previousValues
            watchState.previousValues = values
            watchState.epoch = instance.epoch
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
            let context = instance.context
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for change in changed {
                        if cancellation.isCancelled { break }
                        try await self.runBindings(watch[change.path] ?? .undefined, context: context) { cancellation.isCancelled }
                    }
                } catch {
                    Diagnostics.error(Actions.message(of: error).javaScriptString)
                }
                self.progress += 1
            }
        }
    }
}
