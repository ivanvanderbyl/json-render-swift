import Testing
@testable import JSONRender

// Ports upstream tests from packages/react/src/renderer.test.tsx,
// chained-actions.test.tsx, repeat-filter.test.tsx and directives.test.tsx
// (json-render 0.21.1). Upstream renders React components into a DOM; these
// ports drive the UI-free Runtime and assert on the render tree it produces,
// which is what the SwiftUI renderer draws.

@MainActor
@Suite("renderer.test.tsx › Renderer")
struct RendererTests {
    @Test("renders null for null spec")
    func rendersNothingForNilSpec() {
        let runtime = Runtime()
        runtime.render(nil, components: ComponentTypes([]))
        #expect(runtime.tree == nil)
    }

    @Test("renders null for spec without root")
    func rendersNothingWithoutRoot() {
        let runtime = Runtime()
        runtime.render(Spec(root: "", elements: [:]), components: ComponentTypes([]))
        #expect(runtime.tree == nil)
    }

    @Test("accepts loading prop")
    func acceptsLoading() {
        let runtime = Runtime()
        let spec = Spec(root: "a", elements: ["a": ["type": "Text", "props": [:], "children": []]])
        runtime.render(spec, components: ComponentTypes(["Text"]), loading: true)
        #expect(runtime.loading)
        #expect(runtime.tree?.loading == true)
    }

    @Test("accepts fallback prop")
    func acceptsFallback() {
        let runtime = Runtime()
        let spec = Spec(root: "a", elements: ["a": ["type": "Unknown", "props": [:], "children": []]])
        runtime.render(spec, components: ComponentTypes([], fallback: true))
        #expect(runtime.tree?.status == .rendered)
        #expect(runtime.tree?.type == "Unknown")
    }

    @Test("renders named slots through defineRegistry")
    func rendersNamedSlots() throws {
        let runtime = Runtime()
        let spec = Spec(root: "layout", elements: [
            "layout": ["type": "Layout", "props": [:], "children": ["main"], "slots": ["header": ["header"], "footer": ["footer"]]],
            "header": ["type": "Text", "props": ["text": "Header"]],
            "main": ["type": "Text", "props": ["text": "Main"]],
            "footer": ["type": "Text", "props": ["text": "Footer"]],
        ])
        runtime.render(spec, components: ComponentTypes(["Layout", "Text"], slots: ["Layout": ["default", "header", "footer"], "Text": []]))
        let layout = try #require(runtime.tree)
        #expect(layout.slots.first { $0.name == "header" }?.nodes.map { $0.text() } == ["Header"])
        #expect(layout.children.map { $0.text() } == ["Main"])
        #expect(layout.slots.first { $0.name == "footer" }?.nodes.map { $0.text() } == ["Footer"])
    }

    @Test("resolves nested repeat statePath %s from parent $item scope", arguments: ["subitems", "/subitems"])
    func resolvesNestedRepeatStatePath(itemPath: String) throws {
        let spec = Spec([
            "root": "groups",
            "state": ["groups": [["subitems": [["label": "a1"], ["label": "a2"]]], ["subitems": [["label": "b1"]]]]],
            "elements": [
                "groups": ["type": "Group", "props": [:], "repeat": ["statePath": "/groups"], "children": ["subitems"]],
                "subitems": ["type": "Group", "props": [:], "repeat": ["statePath": ["$item": .string(itemPath)]], "children": ["label"]],
                "label": ["type": "Text", "props": ["text": ["$item": "label"]]],
            ],
        ])
        let runtime = Runtime(initialState: spec.state.objectValue ?? [:])
        runtime.render(spec, components: ComponentTypes(["Group", "Text"]))
        let tree = try #require(runtime.tree)
        #expect(tree.rendered("Text").map { $0.text() } == ["a1", "a2", "b1"])
    }

    @Test("does not fall back to root state for $item outside repeat scope")
    func doesNotFallBackOutsideRepeatScope() throws {
        let spec = Spec([
            "root": "items",
            "state": ["items": [["label": "must-not-render"]]],
            "elements": [
                "items": ["type": "Group", "props": [:], "repeat": ["statePath": ["$item": "items"]], "children": ["label"]],
                "label": ["type": "Text", "props": ["text": ["$item": "label"]]],
            ],
        ])
        let recorder = DiagnosticsRecorder()
        let runtime = Runtime(initialState: spec.state.objectValue ?? [:])
        recorder.record { runtime.render(spec, components: ComponentTypes(["Group", "Text"])) }
        #expect(try #require(runtime.tree).rendered("Text").isEmpty)
        #expect(recorder.warnings.contains("[json-render] $item in repeat.statePath used outside of a repeat scope"))
    }
}

@MainActor
@Suite("chained-actions.test.tsx › chained actions: live $state resolution (#141)")
struct ChainedActionsTests {
    private func pressMain(_ spec: Spec, handlers: [String: ActionHandler] = [:]) async throws -> Runtime {
        let runtime = Runtime(initialState: spec.state.objectValue ?? [:], handlers: handlers)
        runtime.render(spec, components: ComponentTypes(["Button", "Text"]))
        try await runtime.emit("press", nodeID: "main")
        await runtime.settle()
        return runtime
    }

    @Test("setState after pushState sees the post-push value via $state")
    func setStateAfterPushState() async throws {
        let spec = Spec([
            "state": ["items": ["initial"], "observed": "not yet set"],
            "root": "main",
            "elements": ["main": ["type": "Button", "props": ["label": "Add Item"], "on": ["press": [
                ["action": "pushState", "params": ["statePath": "/items", "value": "new-item"]],
                ["action": "setState", "params": ["statePath": "/observed", "value": ["$state": "/items"]]],
            ]]]],
        ])
        let runtime = try await pressMain(spec)
        #expect(runtime.state["items"] == ["initial", "new-item"])
        #expect(runtime.state["observed"] == ["initial", "new-item"])
    }

    @Test("multiple pushState + setState chain resolves correctly")
    func multiplePushStates() async throws {
        let spec = Spec([
            "state": ["items": [], "snapshot": nil],
            "root": "main",
            "elements": ["main": ["type": "Button", "props": ["label": "Go"], "on": ["press": [
                ["action": "pushState", "params": ["statePath": "/items", "value": "a"]],
                ["action": "pushState", "params": ["statePath": "/items", "value": "b"]],
                ["action": "setState", "params": ["statePath": "/snapshot", "value": ["$state": "/items"]]],
            ]]]],
        ])
        let runtime = try await pressMain(spec)
        #expect(runtime.state["items"] == ["a", "b"])
        #expect(runtime.state["snapshot"] == ["a", "b"])
    }

    @Test("setState reading a path mutated by an earlier setState sees fresh value")
    func setStateReadsFreshValue() async throws {
        let spec = Spec([
            "state": ["counter": 0, "counterCopy": -1],
            "root": "main",
            "elements": ["main": ["type": "Button", "props": ["label": "Go"], "on": ["press": [
                ["action": "setState", "params": ["statePath": "/counter", "value": 42]],
                ["action": "setState", "params": ["statePath": "/counterCopy", "value": ["$state": "/counter"]]],
            ]]]],
        ])
        let runtime = try await pressMain(spec)
        #expect(runtime.state["counter"] == 42)
        #expect(runtime.state["counterCopy"] == 42)
    }

    @Test("forwards params to a named onSuccess action (#301)")
    func forwardsOnSuccessParams() async throws {
        let toast = CallRecorder()
        let spec = Spec(root: "main", elements: ["main": ["type": "Button", "props": ["label": "Save"], "on": ["press": [
            "action": "save",
            "onSuccess": ["action": "toast", "params": ["message": "Saved!"]],
        ]]]])
        _ = try await pressMain(spec, handlers: ["save": { _ in .undefined }, "toast": toast.handler()])
        #expect(toast.calls == [["message": "Saved!"]])
    }
}

private let tasks: JSONValue = [
    ["id": "1", "title": "Auth flow", "status": "todo"],
    ["id": "2", "title": "Push notifications", "status": "in-progress"],
    ["id": "3", "title": "Dark mode", "status": "todo"],
    ["id": "4", "title": "App icon", "status": "done"],
]

@MainActor
private func mountTasks(_ spec: Spec) throws -> RenderNode? {
    let runtime = Runtime(initialState: spec.state.objectValue ?? [:])
    runtime.render(spec, components: ComponentTypes(["Stack", "Text"]))
    return runtime.tree
}

@MainActor
@Suite("repeat-filter.test.tsx › repeat with $item visible on the container (filtered list)")
struct RepeatFilterTests {
    private func column(visible: JSONValue = .undefined, card: JSONObject = ["type": "Text", "props": ["text": ["$item": "title"]], "children": []]) -> Spec {
        var column: JSONObject = ["type": "Stack", "props": [:], "repeat": ["statePath": "/tasks", "key": "id"], "children": ["card"]]
        if !visible.isUndefined { column["visible"] = visible }
        return Spec(["root": "column", "state": ["tasks": tasks], "elements": ["column": .object(column), "card": .object(card)]])
    }

    @Test("renders only the items matching the filter")
    func rendersMatchingItems() throws {
        let tree = try #require(try mountTasks(column(visible: ["$item": "status", "eq": "todo"])))
        #expect(tree.rendered("Text").map { $0.text() } == ["Auth flow", "Dark mode"])
    }

    @Test("renders every item without a filter")
    func rendersEveryItem() throws {
        let tree = try #require(try mountTasks(column()))
        #expect(tree.rendered("Text").count == 4)
    }

    @Test("still hides the whole list for a container-level $state condition")
    func hidesListForStateCondition() throws {
        let spec = Spec([
            "root": "column",
            "state": ["tasks": tasks, "showTasks": false],
            "elements": [
                "column": ["type": "Stack", "props": [:], "repeat": ["statePath": "/tasks", "key": "id"], "visible": ["$state": "/showTasks", "eq": true], "children": ["card"]],
                "card": ["type": "Text", "props": ["text": ["$item": "title"]], "children": []],
            ],
        ])
        let tree = try #require(try mountTasks(spec))
        #expect(tree.rendered("Text").isEmpty)
    }

    @Test("keeps per-child $item visible working inside the repeat scope")
    func keepsChildItemVisibility() throws {
        let tree = try #require(try mountTasks(column(card: [
            "type": "Text", "props": ["text": ["$item": "title"]], "visible": ["$item": "status", "eq": "done"], "children": [],
        ])))
        #expect(tree.rendered("Text").map { $0.text() } == ["App icon"])
    }
}

@MainActor
@Suite("repeat-filter.test.tsx › mixed container/item visibility on repeat containers")
struct RepeatFilterMixedVisibilityTests {
    private func mixedSpec(_ showTasks: Bool) -> Spec {
        Spec([
            "root": "column",
            "state": ["tasks": tasks, "showTasks": .bool(showTasks)],
            "elements": [
                "column": [
                    "type": "Stack", "props": [:], "repeat": ["statePath": "/tasks", "key": "id"],
                    "visible": ["$and": [["$state": "/showTasks", "eq": true], ["$item": "status", "eq": "todo"]]],
                    "children": ["card"],
                ],
                "card": ["type": "Text", "props": ["text": ["$item": "title"]], "children": []],
            ],
        ])
    }

    @Test("hides the container shell when the $state gate is false")
    func hidesShell() throws {
        let tree = try #require(try mountTasks(mixedSpec(false)))
        #expect(tree.rendered("Stack").isEmpty)
        #expect(tree.rendered("Text").isEmpty)
    }

    @Test("filters items when the $state gate is true")
    func filtersItems() throws {
        let tree = try #require(try mountTasks(mixedSpec(true)))
        #expect(tree.rendered("Stack").count == 1)
        #expect(tree.rendered("Text").map { $0.text() } == ["Auth flow", "Dark mode"])
    }
}

@MainActor
@Suite("directives.test.tsx › directives in React renderer")
struct RendererDirectiveTests {
    let directives: [DirectiveDefinition]

    init() throws {
        directives = [
            try DirectiveDefinition(name: "$double", description: "Double a numeric value.") { value, context in
                .number(try PropExpression.resolve(value["$double"], in: context).javaScriptNumber * 2)
            },
            try DirectiveDefinition(name: "$upper") { value, context in
                .string(try PropExpression.resolve(value["$upper"], in: context).javaScriptString.uppercased())
            },
        ]
    }

    @Test("resolves a custom directive in rendered props")
    func resolvesDirective() throws {
        let runtime = Runtime(directives: directives)
        runtime.render(Spec(root: "main", elements: ["main": ["type": "Text", "props": ["text": ["$upper": "hello"]], "children": []]]), components: ComponentTypes(["Text"]))
        #expect(try #require(runtime.tree).text() == "HELLO")
    }

    @Test("resolves a directive that reads from state")
    func resolvesDirectiveFromState() throws {
        let runtime = Runtime(initialState: ["count": 7], directives: directives)
        runtime.render(
            Spec(root: "main", elements: ["main": ["type": "Text", "props": ["text": ["$double": ["$state": "/count"]]], "children": []]], state: ["count": 7]),
            components: ComponentTypes(["Text"])
        )
        #expect(try #require(runtime.tree).text() == "14")
    }

    @Test("renders without directives (backward compat)")
    func rendersWithoutDirectives() throws {
        let runtime = Runtime()
        runtime.render(Spec(root: "main", elements: ["main": ["type": "Text", "props": ["text": "plain"], "children": []]]), components: ComponentTypes(["Text"]))
        #expect(try #require(runtime.tree).text() == "plain")
    }
}
