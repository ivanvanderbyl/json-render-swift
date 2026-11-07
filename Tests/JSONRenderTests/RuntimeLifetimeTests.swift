import Testing
@testable import JSONRender

@MainActor
@Suite("Runtime asynchronous action lifetime")
struct RuntimeLifetimeTests {
    enum Completion: String, Sendable, CaseIterable {
        case success, failure, nested
    }

    @Test("retains a released runtime through handler completion", arguments: Completion.allCases)
    func retainsRuntimeThroughCompletion(_ completion: Completion) async {
        let gate = HandlerGate()
        let settled = Settlement()
        let probe = WeakRuntime()
        let name = "lifetime-\(completion.rawValue)"
        let unsubscribe = ActionObservers.register(ActionObserver(onSettle: { info in
            guard info.name == .string(name) else { return }
            settled.finish(state: probe.value?.store.snapshot, loading: probe.value?.loadingActions)
        }))
        defer { unsubscribe() }

        var runtime: Runtime? = Runtime(initialState: ["saved": false])
        probe.value = runtime
        runtime?.registerHandler(name) { _ in
            if await gate.suspend() { throw JavaScriptError.error("Save failed") }
            return true
        }
        runtime?.registerHandler("lifetime-follow-up") { _ in true }
        var binding: JSONObject = ["action": .string(name)]
        switch completion {
        case .success: binding["onSuccess"] = ["set": ["/saved": true]]
        case .failure: binding["onError"] = ["set": ["/saved": "$error.message"]]
        case .nested:
            binding["onSuccess"] = ["action": "lifetime-follow-up", "onSuccess": ["set": ["/saved": true]]]
        }
        runtime?.render(Spec(root: "save", elements: [
            "save": ["type": "Button", "on": ["press": .object(binding)]],
        ]), components: ComponentTypes(["Button"]))
        runtime?.fire("press", nodeID: "save")
        await gate.waitForStart()
        runtime = nil

        let retained = probe.value != nil
        #expect(retained, "An accepted asynchronous action must own its runtime until it settles")
        // A failed retention assertion must not invoke an unowned context in
        // the old implementation: finish without its configured callback.
        gate.resume(throwing: retained ? completion == .failure : completion != .failure)
        guard retained else { return }
        await settled.wait()
        #expect(settled.state?["saved"] == (completion == .failure ? "Save failed" : true))
        #expect(settled.loading?.isEmpty == true)
    }
}

@MainActor
private final class WeakRuntime {
    weak var value: Runtime?
}

@MainActor
private final class HandlerGate {
    private var handler: CheckedContinuation<Bool, Never>?
    private var start: CheckedContinuation<Void, Never>?

    func suspend() async -> Bool {
        await withCheckedContinuation { continuation in
            handler = continuation
            start?.resume()
            start = nil
        }
    }

    func waitForStart() async {
        guard handler == nil else { return }
        await withCheckedContinuation { start = $0 }
    }

    func resume(throwing: Bool) {
        handler?.resume(returning: throwing)
        handler = nil
    }
}

@MainActor
private final class Settlement {
    var state: JSONObject?
    var loading: Set<String>?
    private var continuation: CheckedContinuation<Void, Never>?

    func finish(state: JSONObject?, loading: Set<String>?) {
        self.state = state
        self.loading = loading
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        guard state == nil else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
