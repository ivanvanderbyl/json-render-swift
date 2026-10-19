import Testing
@testable import JSONRender

// Ports upstream tests from packages/react/src/dynamic-forms.test.tsx,
// contexts/state.test.tsx and contexts/visibility.test.tsx (json-render 0.21.1).
// Upstream's stub components become test code that calls the same runtime
// APIs those components call: emit, binding writes and field validation.

private let formTypes = ComponentTypes(["Stack", "Button", "Text", "Input", "Select"])

@MainActor
private func mount(_ spec: Spec, handlers: [String: ActionHandler] = [:], functions: [String: ComputedFunction] = [:]) async -> Runtime {
    let runtime = Runtime(initialState: spec.state.objectValue ?? [:], handlers: handlers, functions: functions)
    runtime.render(spec, components: formTypes)
    // Field components register their validation once mounted.
    for node in runtime.tree?.allNodes ?? [] where node.type == "Input" || node.type == "Select" {
        registerFieldValidation(node, in: runtime)
    }
    await runtime.settle()
    return runtime
}

@MainActor
@Suite("dynamic-forms.test.tsx › $computed expressions in rendering")
struct DynamicFormsComputedTests {
    @Test("resolves a $computed prop using provided functions")
    func resolvesComputed() async throws {
        let spec = Spec([
            "state": ["first": "Jane", "last": "Doe"],
            "root": "main",
            "elements": ["main": ["type": "Text", "props": ["text": [
                "$computed": "fullName", "args": ["first": ["$state": "/first"], "last": ["$state": "/last"]],
            ]], "children": []]],
        ])
        let runtime = await mount(spec, functions: [
            "fullName": { args in .string("\((args["first"] ?? .undefined).javaScriptString) \((args["last"] ?? .undefined).javaScriptString)") },
        ])
        #expect(try #require(runtime.tree).text() == "Jane Doe")
    }

    @Test("renders gracefully when functions prop is omitted")
    func rendersWithoutFunctions() async throws {
        let recorder = DiagnosticsRecorder()
        let spec = Spec(["state": [:], "root": "main", "elements": ["main": ["type": "Text", "props": ["text": ["$computed": "missing"]], "children": []]]])
        let runtime = await recorder.record { await mount(spec) }
        #expect(try #require(runtime.tree).text() == "")
    }
}

@MainActor
@Suite("dynamic-forms.test.tsx › $template expressions in rendering")
struct DynamicFormsTemplateTests {
    @Test("interpolates state values into a template string")
    func interpolatesTemplate() async throws {
        let spec = Spec([
            "state": ["user": ["name": "Alice"], "count": 3],
            "root": "main",
            "elements": ["main": ["type": "Text", "props": ["text": ["$template": "Hello, ${/user/name}! You have ${/count} messages."]], "children": []]],
        ])
        let runtime = await mount(spec)
        #expect(try #require(runtime.tree).text() == "Hello, Alice! You have 3 messages.")
    }

    @Test("resolves missing paths to empty string")
    func resolvesMissingPaths() async throws {
        let spec = Spec(["state": [:], "root": "main", "elements": ["main": ["type": "Text", "props": ["text": ["$template": "Hi ${/name}!"]], "children": []]]])
        let runtime = await mount(spec)
        #expect(try #require(runtime.tree).text() == "Hi !")
    }
}

@MainActor
@Suite("dynamic-forms.test.tsx › watchers (watch field)")
struct DynamicFormsWatcherTests {
    @Test("does not fire on initial render, fires when watched state changes")
    func firesOnlyOnChange() async throws {
        let loadCities = CallRecorder()
        let spec = Spec([
            "state": ["form": ["country": ""], "citiesLoaded": false],
            "root": "wrapper",
            "elements": [
                "wrapper": ["type": "Stack", "props": [:], "children": ["btn", "watcher"]],
                "btn": ["type": "Button", "props": ["label": "Set Country"], "on": ["press": [
                    ["action": "setState", "params": ["statePath": "/form/country", "value": "US"]],
                ]], "children": []],
                "watcher": ["type": "Select", "props": ["value": ["$state": "/form/country"]], "watch": [
                    "/form/country": ["action": "loadCities", "params": ["country": ["$state": "/form/country"]]],
                ], "children": []],
            ],
        ])
        let runtime = await mount(spec, handlers: ["loadCities": loadCities.handler()])
        #expect(loadCities.calls.isEmpty)
        try await runtime.emit("press", nodeID: "wrapper/btn")
        await runtime.settle()
        #expect(loadCities.calls.count == 1)
        #expect(loadCities.calls.first?["country"] == "US")
    }

    @Test("fires multiple action bindings on the same watch path")
    func firesMultipleBindings() async throws {
        let action1 = CallRecorder()
        let action2 = CallRecorder()
        let spec = Spec([
            "state": ["value": "a"],
            "root": "wrapper",
            "elements": [
                "wrapper": ["type": "Stack", "props": [:], "children": ["btn", "watcher"]],
                "btn": ["type": "Button", "props": ["label": "Change"], "on": ["press": [
                    ["action": "setState", "params": ["statePath": "/value", "value": "b"]],
                ]], "children": []],
                "watcher": ["type": "Text", "props": ["text": ["$state": "/value"]], "watch": [
                    "/value": [["action": "action1"], ["action": "action2"]],
                ], "children": []],
            ],
        ])
        let runtime = await mount(spec, handlers: ["action1": action1.handler(), "action2": action2.handler()])
        try await runtime.emit("press", nodeID: "wrapper/btn")
        await runtime.settle()
        #expect(action1.calls.count == 1)
        #expect(action2.calls.count == 1)
    }
}

@MainActor
@Suite("dynamic-forms.test.tsx › validateForm action")
struct DynamicFormsValidateFormTests {
    private func formSpec(state: JSONObject, input: JSONObject, press: JSONValue) -> Spec {
        Spec([
            "state": .object(state),
            "root": "wrapper",
            "elements": [
                "wrapper": ["type": "Stack", "props": [:], "children": ["input", "submitBtn"]],
                "input": ["type": "Input", "props": .object(input), "children": []],
                "submitBtn": ["type": "Button", "props": ["label": "Submit"], "on": ["press": press], "children": []],
            ],
        ])
    }

    @Test("writes { valid: false } when a required field is empty")
    func writesInvalid() async throws {
        let spec = formSpec(
            state: ["form": ["email": ""], "result": nil],
            input: ["label": "Email", "value": ["$bindState": "/form/email"], "checks": [["type": "required", "message": "Email is required"]]],
            press: [["action": "validateForm", "params": ["statePath": "/result"]]]
        )
        let runtime = await mount(spec)
        try await runtime.emit("press", nodeID: "wrapper/submitBtn")
        await runtime.settle()
        #expect(runtime.state["result"] == ["valid": false, "errors": ["/form/email": ["Email is required"]]])
    }

    @Test("writes { valid: true } when all fields pass validation")
    func writesValid() async throws {
        let spec = formSpec(
            state: ["form": ["email": "test@example.com"], "result": nil],
            input: ["label": "Email", "value": ["$bindState": "/form/email"], "checks": [["type": "required", "message": "Email is required"]]],
            press: [["action": "validateForm", "params": ["statePath": "/result"]]]
        )
        let runtime = await mount(spec)
        try await runtime.emit("press", nodeID: "wrapper/submitBtn")
        await runtime.settle()
        #expect(runtime.state["result"] == ["valid": true, "errors": [:]])
    }

    @Test("defaults to /formValidation when no statePath is provided")
    func defaultsStatePath() async throws {
        let spec = formSpec(
            state: ["form": ["name": "filled"]],
            input: ["label": "Name", "value": ["$bindState": "/form/name"], "checks": [["type": "required", "message": "Required"]]],
            press: [["action": "validateForm"]]
        )
        let runtime = await mount(spec)
        try await runtime.emit("press", nodeID: "wrapper/submitBtn")
        await runtime.settle()
        #expect(runtime.state["formValidation"] == ["valid": true, "errors": [:]])
    }
}

@MainActor
@Suite("dynamic-forms.test.tsx › Select validate-on-change sees the new value, not the stale value")
struct DynamicFormsSelectTests {
    /// What upstream's ValidatedSelect does on change: write the bound value,
    /// then validate synchronously.
    private func select(_ value: JSONValue, on node: RenderNode, in runtime: Runtime) throws {
        let path = try #require(node.bindings?["value"])
        runtime.set(path, value)
        try runtime.validation.validate(path, config: ["checks": node.props["checks"] ?? [], "validateOn": "change"])
    }

    private func selectSpec(state: JSONObject, name: String, label: String, options: JSONValue, message: String) -> Spec {
        Spec([
            "state": .object(state),
            "root": "wrapper",
            "elements": [
                "wrapper": ["type": "Stack", "props": [:], "children": ["select"]],
                "select": ["type": "Select", "props": [
                    "label": .string(label), "name": .string(name), "options": options,
                    "value": ["$bindState": .string("/form/\(name)")],
                    "checks": [["type": "required", "message": .string(message)]], "validateOn": "change",
                ], "children": []],
            ],
        ])
    }

    @Test("does not show 'required' error when selecting the first value")
    func noErrorOnFirstSelection() async throws {
        let runtime = await mount(selectSpec(state: ["form": ["country": ""]], name: "country", label: "Country", options: ["US", "Canada", "UK"], message: "Country is required"))
        try select("US", on: try #require(runtime.tree?.node("select")), in: runtime)
        await runtime.settle()
        #expect(runtime.state["form"]?["country"] == "US")
        #expect(runtime.validation.state(for: "/form/country").result?.errors.isEmpty == true)
    }

    @Test("does not show 'required' error when selecting the first city after country change resets it")
    func noErrorAfterReset() async throws {
        let runtime = await mount(selectSpec(
            state: ["form": ["country": "US", "city": ""], "availableCities": ["New York", "Chicago"]],
            name: "city", label: "City", options: ["New York", "Chicago"], message: "City is required"
        ))
        try select("New York", on: try #require(runtime.tree?.node("select")), in: runtime)
        await runtime.settle()
        #expect(runtime.state["form"]?["city"] == "New York")
        #expect(runtime.validation.state(for: "/form/city").result?.errors.isEmpty == true)
    }
}

@MainActor
@Suite("contexts/state.test.tsx › state re-exports (smoke test)")
struct StateContextTests {
    @Test("StateProvider + useStateStore round-trip")
    func roundTrip() {
        let runtime = Runtime(initialState: ["count": 0])
        #expect(runtime.get("/count") == 0)
        runtime.set("/count", 42)
        #expect(runtime.state["count"] == 42)
    }

    @Test("useStateValue reads from state")
    func readsValue() {
        let runtime = Runtime(initialState: ["name": "Alice"])
        #expect(runtime.get("/name") == "Alice")
    }

    @Test("useStateBinding returns value and setter")
    func returnsBinding() {
        let runtime = Runtime(initialState: ["x": 1])
        let binding = runtime.binding("/x")
        #expect(binding.value == 1)
        binding.set(2)
        #expect(runtime.get("/x") == 2)
    }
}

@MainActor
@Suite("contexts/visibility.test.tsx › useVisibility")
struct VisibilityContextTests {
    // N/A: "provides isVisible function": a TypeScript typeof check; the Swift
    // method always exists.

    @Test("provides visibility context")
    func providesContext() {
        let runtime = Runtime(initialState: ["test": true])
        #expect(runtime.visibilityContext.state == ["test": true])
    }
}

@MainActor
@Suite("contexts/visibility.test.tsx › useIsVisible")
struct IsVisibleContextTests {
    @Test("returns true for undefined condition")
    func undefinedIsVisible() {
        #expect(Runtime().isVisible(.undefined))
    }

    @Test("returns true for true condition")
    func trueIsVisible() {
        #expect(Runtime().isVisible(true))
    }

    @Test("returns false for false condition")
    func falseIsHidden() {
        #expect(!Runtime().isVisible(false))
    }

    @Test("evaluates $state conditions against data")
    func evaluatesStateConditions() {
        #expect(Runtime(initialState: ["isVisible": true]).isVisible(["$state": "/isVisible"]))
        #expect(!Runtime(initialState: ["isVisible": false]).isVisible(["$state": "/isVisible"]))
    }

    @Test("evaluates equality conditions")
    func evaluatesEquality() {
        #expect(Runtime(initialState: ["count": 1]).isVisible(["$state": "/count", "eq": 1]))
    }

    @Test("evaluates array conditions (implicit AND)")
    func evaluatesArrays() {
        let runtime = Runtime(initialState: ["user": ["isAdmin": true], "count": 5])
        #expect(runtime.isVisible([["$state": "/user/isAdmin"], ["$state": "/count", "eq": 5]]))
    }
}
