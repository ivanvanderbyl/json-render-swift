import Foundation
import Testing
@testable import JSONRender

// Ports upstream tests from packages/react/src/streaming-render.test.tsx
// (json-render 0.21.1).
//
// N/A: "does not execute untouched catalog components for each patch":
//      counts React component renders; SwiftUI decides when views re-evaluate.
// N/A: "keeps binding identity stable across state writes": guards against a
//      React effect loop on unstable binding objects; Swift bindings are values.
// N/A: "preserves state context updates for catalog components": counts React
//      component renders after a state write.
// N/A: "supports non-serializable resolved state and repeat items": JSON
//      values cannot be cyclic or hold a BigInt.

private let elementCount = 26
private let patchCount = 200

private func makeSpec() -> Spec {
    let children = (0..<elementCount).map { "metric-\($0)" }
    var elements: JSONObject = ["root": ["type": "Stack", "props": [:], "children": .array(JSONArray(children.map(JSONValue.string)))]]
    var state = JSONObject()
    for (index, key) in children.enumerated() {
        elements[key] = ["type": "Metric", "props": ["value": ["$bindState": .string("/\(key)")], "revision": 0]]
        state[key] = .number(Double(index))
    }
    return Spec(["root": "root", "state": .object(state), "elements": .object(elements)])
}

private func patchPart(_ revision: Int) -> JSONObject {
    ["type": "data-spec", "data": ["type": "patch", "patch": [
        "op": "replace", "path": "/elements/metric-0/props/revision", "value": .number(Double(revision)),
    ]]]
}

/// Counts calls, standing in for a counter captured by a JavaScript closure.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

@MainActor
@Suite("streaming-render.test.tsx › streaming render stability")
struct StreamingRenderTests {
    @Test("does not execute untouched element renderers for each patch")
    func doesNotReresolveUntouchedElements() throws {
        let executions = Counter()
        var first = try #require(makeSpec().object["elements"]?.objectValue)
        for key in first.keys where key != "root" {
            var element = first[key]!.objectValue!
            var props = element["props"]!.objectValue!
            props["probe"] = ["$count": .string(key)]
            element["props"] = .object(props)
            first[key] = .object(element)
        }
        var base = makeSpec()
        base.elements = first
        var parts: [JSONObject] = [["type": "data-spec", "data": ["type": "flat", "spec": .object(base.object)]]]
        let count = try DirectiveDefinition(name: "$count") { value, _ in
            executions.increment()
            return value["$count"]
        }
        let initial = try #require(try MessageParts.spec(from: parts))
        let runtime = Runtime(initialState: initial.state.objectValue ?? [:], directives: [count])
        let components = ComponentTypes(["Stack", "Metric"])
        runtime.render(initial, components: components)
        for revision in 1...patchCount {
            parts.append(patchPart(revision))
            let spec = try #require(try MessageParts.spec(from: parts))
            runtime.setInitialState(spec.state.objectValue ?? [:])
            runtime.render(spec, components: components)
        }
        #expect(executions.value == elementCount + patchCount)
    }

    @Test("renders a child that becomes available in a later complete spec")
    func rendersLateChild() throws {
        let runtime = Runtime()
        let components = ComponentTypes(["Stack", "Metric"])
        runtime.render(Spec(root: "root", elements: ["root": ["type": "Stack", "props": [:], "children": ["late"]]]), components: components, loading: true)
        #expect(try #require(runtime.tree).rendered("Metric").isEmpty)
        runtime.render(
            Spec(root: "root", elements: [
                "root": ["type": "Stack", "props": [:], "children": ["late"]],
                "late": ["type": "Metric", "props": ["revision": 1]],
            ]),
            components: components,
            loading: false
        )
        #expect(try #require(runtime.tree).rendered("Metric").map { $0.text("revision") } == ["1"])
    }

    @Test("updates direct renderer consumers with fresh complete specs")
    func updatesWithFreshSpecs() throws {
        let first = makeSpec()
        let runtime = Runtime(initialState: first.state.objectValue ?? [:])
        let components = ComponentTypes(["Stack", "Metric"])
        runtime.render(first, components: components)
        var next = first
        var elements = next.elements
        var metric = elements["metric-0"]!.objectValue!
        var props = metric["props"]!.objectValue!
        props["revision"] = 9
        metric["props"] = .object(props)
        elements["metric-0"] = .object(metric)
        next.elements = elements
        runtime.setInitialState(next.state.objectValue ?? [:])
        runtime.render(next, components: components)
        #expect(try #require(runtime.tree).rendered("Metric").first?.text("revision") == "9")
    }

    @Test("does not preserve stale prop keys with undefined values")
    func dropsStalePropKeys() throws {
        let runtime = Runtime()
        let components = ComponentTypes(["Value"])
        runtime.render(Spec(root: "value", elements: ["value": ["type": "Value", "props": ["foo": .undefined]]]), components: components)
        #expect(try #require(runtime.tree).props.keys == ["foo"])
        runtime.render(Spec(root: "value", elements: ["value": ["type": "Value", "props": ["bar": .undefined]]]), components: components)
        #expect(try #require(runtime.tree).props.keys == ["bar"])
    }

    @Test("recovers when props arrive after the element type")
    func recoversWhenPropsArriveLate() throws {
        var parts: [JSONObject] = [
            ["type": "data-spec", "data": ["type": "patch", "patch": ["op": "add", "path": "/root", "value": "value"]]],
            ["type": "data-spec", "data": ["type": "patch", "patch": ["op": "add", "path": "/elements/value", "value": ["type": "Value"]]]],
        ]
        let runtime = Runtime()
        let components = ComponentTypes(["Value"])
        runtime.render(try MessageParts.spec(from: parts), components: components)
        #expect(try #require(runtime.tree).status == .rendered)
        #expect(runtime.tree?.props["label"] == nil)
        parts.append(["type": "data-spec", "data": ["type": "patch", "patch": ["op": "add", "path": "/elements/value/props", "value": ["label": "ready"]]]])
        runtime.render(try MessageParts.spec(from: parts), components: components)
        #expect(try #require(runtime.tree).text("label") == "ready")
    }

    @Test("keeps repeated event callbacks bound to the current item")
    func keepsRepeatCallbacksCurrent() async throws {
        let received = CallRecorder()
        let spec = Spec([
            "root": "list",
            "state": ["items": [["id": "one", "label": "initial"]]],
            "elements": [
                "list": ["type": "List", "props": [:], "repeat": ["statePath": "/items", "key": "id"], "children": ["button"]],
                "button": ["type": "Button", "props": [:], "on": ["press": ["action": "select", "params": [
                    "label": ["$computed": "itemLabel", "args": ["label": ["$item": "label"]]],
                ]]]],
            ],
        ])
        let runtime = Runtime(
            initialState: spec.state.objectValue ?? [:],
            handlers: ["select": received.handler()],
            functions: ["itemLabel": { args in args["label"] ?? .undefined }]
        )
        runtime.render(spec, components: ComponentTypes(["List", "Button"]))
        runtime.set("/items/0", ["id": "one", "label": "updated"])
        await runtime.settle()
        try await runtime.emit("press", nodeID: "list/[one]/button")
        #expect(received.calls.map { $0["label"] ?? .undefined } == ["updated"])
    }

    @Test("refreshes resolved props when functions and directives change")
    func refreshesFunctionsAndDirectives() throws {
        let spec = Spec(root: "value", elements: ["value": ["type": "Value", "props": [
            "computed": ["$computed": "label"], "directed": ["$prefix": "value"],
        ]]])
        func prefix(_ text: String) throws -> DirectiveDefinition {
            try DirectiveDefinition(name: "$prefix") { value, context in
                .string("\(text)-\(try PropExpression.resolve(value["$prefix"], in: context).javaScriptString)")
            }
        }
        let runtime = Runtime(functions: ["label": { _ in "first" }], directives: [try prefix("first")])
        let components = ComponentTypes(["Value"])
        runtime.render(spec, components: components)
        #expect(runtime.tree.map { "\($0.text("computed")):\($0.text("directed"))" } == "first:first-value")
        runtime.functions = ["label": { _ in "second" }]
        runtime.directives = [try prefix("second")]
        runtime.render(spec, components: components)
        #expect(runtime.tree.map { "\($0.text("computed")):\($0.text("directed"))" } == "second:second-value")
    }

    @Test("keeps event callbacks fresh when functions and directives change")
    func keepsCallbacksFresh() async throws {
        let received = CallRecorder()
        let spec = Spec(root: "button", elements: ["button": ["type": "Button", "props": [:], "on": ["press": ["action": "select", "params": [
            "computed": ["$computed": "label"], "directed": ["$prefix": "value"],
        ]]]]])
        func prefix(_ text: String) throws -> DirectiveDefinition {
            try DirectiveDefinition(name: "$prefix") { value, _ in .string("\(text)-\(value["$prefix"].javaScriptString)") }
        }
        let runtime = Runtime(handlers: ["select": received.handler()], functions: ["label": { _ in "first" }], directives: [try prefix("first")])
        let components = ComponentTypes(["Button"])
        runtime.render(spec, components: components)
        runtime.functions = ["label": { _ in "second" }]
        runtime.directives = [try prefix("second")]
        runtime.render(spec, components: components)
        try await runtime.emit("press", nodeID: "button")
        #expect(received.calls == [["computed": "second", "directed": "second-value"]])
    }

    @Test("propagates shared-child updates through a DAG")
    func propagatesSharedChildUpdates() throws {
        let first = Spec(root: "root", elements: [
            "root": ["type": "Stack", "props": [:], "children": ["left", "right"]],
            "left": ["type": "Stack", "props": [:], "children": ["shared"]],
            "right": ["type": "Stack", "props": [:], "children": ["shared"]],
            "shared": ["type": "Value", "props": ["revision": 1]],
        ])
        let runtime = Runtime()
        let components = ComponentTypes(["Stack", "Value"])
        runtime.render(first, components: components)
        #expect(try #require(runtime.tree).rendered("Value").map { $0.text("revision") }.joined() == "11")
        var second = first
        var elements = second.elements
        elements["shared"] = ["type": "Value", "props": ["revision": 2]]
        second.elements = elements
        runtime.render(second, components: components)
        #expect(try #require(runtime.tree).rendered("Value").map { $0.text("revision") }.joined() == "22")
    }

    @Test("terminates signature computation for cyclic element graphs")
    func terminatesForCycles() {
        let runtime = Runtime()
        runtime.render(
            Spec(root: "", elements: [
                "first": ["type": "Node", "props": [:], "children": ["second"]],
                "second": ["type": "Node", "props": [:], "children": ["first"]],
            ]),
            components: ComponentTypes(["Node"])
        )
        #expect(runtime.tree == nil)
    }

    @Test("stops a watch action chain when its element unmounts")
    func stopsWatchChainOnUnmount() async throws {
        let firstStarted = Counter()
        let secondCalls = Counter()
        let gate = Gate()
        let first = Spec([
            "root": "root",
            "state": ["value": "initial"],
            "elements": [
                "root": ["type": "Stack", "props": [:], "children": ["watcher"]],
                "watcher": ["type": "Watcher", "props": [:], "watch": ["/value": [["action": "first"], ["action": "second"]]]],
            ],
        ])
        let runtime = Runtime(initialState: first.state.objectValue ?? [:], handlers: [
            "first": { _ in
                firstStarted.increment()
                await gate.wait()
                return .undefined
            },
            "second": { _ in
                secondCalls.increment()
                return .undefined
            },
        ])
        let components = ComponentTypes(["Stack", "Watcher"])
        runtime.render(first, components: components)
        runtime.set("/value", "changed")
        await runtime.settle()
        #expect(firstStarted.value == 1)
        var second = first
        var elements = second.elements
        elements["root"] = ["type": "Stack", "props": [:], "children": []]
        second.elements = elements
        runtime.render(second, components: components)
        await gate.open()
        await runtime.settle()
        #expect(secondCalls.value == 0)
    }

    @Test("recovers a catalog component after a corrective patch")
    func recoversAfterCorrectivePatch() throws {
        let runtime = Runtime()
        let components = ComponentTypes(["Value"])
        runtime.render(Spec(root: "value", elements: ["value": ["type": "Value", "props": ["revision": 0]]]), components: components)
        // The component fails to render its first props, as upstream's throws.
        runtime.reportComponentFailure(nodeID: "value", error: JavaScriptError.error("incomplete"))
        #expect(runtime.tree?.status == .failed)
        runtime.render(Spec(root: "value", elements: ["value": ["type": "Value", "props": ["revision": 1]]]), components: components)
        #expect(runtime.tree?.status == .rendered)
        #expect(runtime.tree?.text("revision") == "1")
    }

    @Test("computes signatures for deep element graphs without recursion")
    func computesDeepSignatures() {
        var elements = JSONObject()
        for index in 0..<12_000 {
            elements["node-\(index)"] = ["type": "Node", "props": [:], "children": index == 11_999 ? [] : [.string("node-\(index + 1)")]]
        }
        let runtime = Runtime()
        runtime.render(Spec(root: "", elements: elements), components: ComponentTypes(["Node"]))
        #expect(runtime.tree == nil)
    }
}

/// An async gate a handler waits on until the test opens it.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
