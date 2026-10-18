import Testing
@testable import JSONRender

// Upstream renders a cyclic spec forever: React keeps adding elements until
// the JavaScript heap runs out and the process crashes. The Swift runtime
// stops at the repeated element instead, and the element that reached it
// fails like a component that throws, so the rest of the spec still draws.

@MainActor
@Suite("Cyclic specs")
struct CycleTests {
    let components = ComponentTypes(["Box", "Text", "List"], slots: ["Box": ["header"]])

    @Test("an element that contains its own ancestor fails and the rest renders")
    func ancestorCycle() throws {
        let runtime = Runtime()
        let recorder = DiagnosticsRecorder()
        recorder.record {
            runtime.render(Spec(root: "a", elements: [
                "a": ["type": "Box", "props": [:], "children": ["b", "text"]],
                "b": ["type": "Box", "props": [:], "children": ["a"]],
                "text": ["type": "Text", "props": ["text": "still here"]],
            ]), components: components)
        }
        let tree = try #require(runtime.tree)
        #expect(tree.status == .rendered)
        #expect(tree.node(id: "a/b")?.status == .failed)
        #expect(tree.node(id: "a/text")?.status == .rendered)
        #expect(recorder.errors == [#"[json-render] Rendering error in <Box>: Element "a" is its own ancestor, so the spec has a cycle"#])
    }

    @Test("an element that lists itself as a child fails")
    func selfCycle() throws {
        let runtime = Runtime()
        DiagnosticsRecorder().record {
            runtime.render(Spec(root: "a", elements: ["a": ["type": "Box", "props": [:], "children": ["a"]]]), components: components)
        }
        #expect(runtime.tree?.status == .failed)
        #expect(runtime.renderError == nil)
    }

    @Test("cycles through slots and repeats are caught")
    func slotAndRepeatCycles() throws {
        let runtime = Runtime(initialState: ["items": [1, 2]])
        DiagnosticsRecorder().record {
            runtime.render(Spec(root: "a", elements: [
                "a": ["type": "Box", "props": [:], "children": ["list"], "slots": ["header": ["a"]]],
                "list": ["type": "List", "props": [:], "repeat": ["statePath": "/items"], "children": ["list"]],
            ]), components: components)
        }
        #expect(runtime.tree?.status == .failed)
    }

    @Test("an element shared by two parents is not a cycle")
    func sharedChildIsNotACycle() throws {
        let runtime = Runtime()
        runtime.render(Spec(root: "a", elements: [
            "a": ["type": "Box", "props": [:], "children": ["b", "c"]],
            "b": ["type": "Box", "props": [:], "children": ["text"]],
            "c": ["type": "Box", "props": [:], "children": ["text"]],
            "text": ["type": "Text", "props": ["text": "shared"]],
        ]), components: components)
        #expect(runtime.tree?.allNodes.allSatisfy { $0.status == .rendered } == true)
    }
}
