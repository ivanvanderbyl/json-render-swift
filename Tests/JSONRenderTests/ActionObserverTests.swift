// Ports upstream tests from packages/core/src/action-observer.test.ts (json-render 0.21.1).
// Suite and test names match the upstream describe and it names.

import Testing
@testable import JSONRender

@MainActor
@Suite("action-observer.test.ts › action observer registry")
struct ActionObserverRegistryTests {
    /// Records each call, like a `vi.fn()` spy.
    final class Spy<Arguments> { var calls: [Arguments] = [] }

    @Test("fires onDispatch for every registered observer")
    func firesOnDispatchForEveryObserver() {
        let a = Spy<ActionDispatchInfo>()
        let b = Spy<ActionDispatchInfo>()
        let unsubA = ActionObservers.register(ActionObserver(onDispatch: { a.calls.append($0) }))
        let unsubB = ActionObservers.register(ActionObserver(onDispatch: { b.calls.append($0) }))

        ActionObservers.notifyDispatch(ActionDispatchInfo(id: "1", name: "foo", at: 10))
        #expect(a.calls.count == 1)
        #expect(b.calls.count == 1)

        unsubA()
        ActionObservers.notifyDispatch(ActionDispatchInfo(id: "2", name: "bar", at: 20))
        #expect(a.calls.count == 1)
        #expect(b.calls.count == 2)

        unsubB()
    }

    @Test("fires onSettle with the same id as dispatch")
    func firesOnSettleWithSameID() {
        let settle = Spy<ActionSettleInfo>()
        let unsub = ActionObservers.register(ActionObserver(onSettle: { settle.calls.append($0) }))

        ActionObservers.notifySettle(ActionSettleInfo(
            id: "abc",
            name: "foo",
            ok: true,
            at: 10,
            durationMs: 3
        ))

        #expect(settle.calls.contains { $0.id == "abc" && $0.ok == true && $0.durationMs == 3 })
        unsub()
    }

    @Test("isolates observer throws")
    func isolatesObserverThrows() {
        let thrower = Spy<ActionDispatchInfo>()
        let good = Spy<ActionDispatchInfo>()
        let unsubA = ActionObservers.register(ActionObserver(onDispatch: {
            thrower.calls.append($0)
            throw JavaScriptError.error("boom")
        }))
        let unsubB = ActionObservers.register(ActionObserver(onDispatch: { good.calls.append($0) }))

        // Captures the console.error report so it stays out of the log, as
        // upstream mocks console.error.
        let console = DiagnosticsRecorder()
        console.record {
            ActionObservers.notifyDispatch(ActionDispatchInfo(id: "1", name: "foo", at: 0))
        }
        #expect(!thrower.calls.isEmpty)
        #expect(!good.calls.isEmpty)
        unsubA()
        unsubB()
    }

    @Test("returns unique dispatch ids")
    func returnsUniqueDispatchIDs() {
        let a = ActionObservers.nextDispatchID()
        let b = ActionObservers.nextDispatchID()
        #expect(a != b)
        #expect(a.wholeMatch(of: /\d+-\d+/.asciiOnlyDigits()) != nil)
    }
}
