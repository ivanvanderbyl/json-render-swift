import Foundation
import Testing
@testable import JSONRender

/// Render scenarios (Conformance/corpus/render.json) replayed through the
/// Swift runtime the way Conformance/src/render/harness.mjs drives upstream's
/// React renderer. After every step the render tree, state, observable log,
/// diagnostics, pending confirmation and field states must match upstream.
@MainActor
@Suite("Conformance: render scenarios")
struct RenderConformanceTests {
    @Test(arguments: Golden.cases("render"))
    func matchesUpstream(_ golden: GoldenCase) async throws {
        let expectedSteps = golden.output["steps"].arrayValue ?? []
        let actualSteps = try await ActionObserverScope.$current.withValue(UUID().uuidString) {
            try await ScenarioRunner(Tagged.decode(golden.input)).run()
        }
        try #require(actualSteps.count == expectedSteps.count, "step count")
        for (index, (expected, actual)) in zip(expectedSteps, actualSteps).enumerated() {
            for field in ["tree", "state", "log", "messages", "pendingConfirmation", "fieldStates"] {
                let label = "\(golden.name) step \(index) \(field)"
                try withDivergence(golden, value: index) {
                    #expect(
                        Tagged.matches(expected[field], actual[field]),
                        "\(label)\n  upstream: \(expected[field])\n  swift:    \(actual[field])"
                    )
                }
            }
        }
    }
}

/// Drives one scenario.
@MainActor
final class ScenarioRunner {
    let scenario: JSONValue
    var spec: Spec
    var loading: Bool
    let components: ComponentTypes
    let fieldTypes: Set<String>
    let throwingTypes: Set<String>
    var log: [JSONValue] = []
    var gates: [String: Gate] = [:]
    let messages = MessageRecorder()
    var runtime: Runtime!

    init(_ scenario: JSONValue) {
        self.scenario = scenario
        spec = Spec(scenario["spec"].objectValue ?? [:])
        loading = scenario["loading"] == true
        var slots: [String: [String]]?
        if case let .object(catalog) = scenario["catalog"]["components"] {
            slots = [:]
            for (name, definition) in catalog { slots?[name] = (definition["slots"].arrayValue ?? []).compactMap(\.stringValue) }
        }
        components = ComponentTypes(
            (scenario["components"].arrayValue ?? []).compactMap(\.stringValue),
            fallback: scenario["fallback"] == true,
            slots: slots
        )
        fieldTypes = Set((scenario["fieldTypes"].arrayValue ?? []).compactMap(\.stringValue))
        throwingTypes = Set((scenario["throwingTypes"].arrayValue ?? []).compactMap(\.stringValue))
    }

    func run() async throws -> [JSONValue] {
        var handlers: [String: ActionHandler] = [:]
        for (name, behaviour) in scenario["handlers"].objectValue ?? [:] {
            if behaviour["pending"] == true { gates[name] = Gate() }
            let gate = gates[name]
            handlers[name] = { [unowned self] params in
                log.append(["event": "handler", "name": .string(name), "params": normalised(.object(params))])
                if case let .string(message) = behaviour["throw"] { throw JavaScriptError.error(message) }
                if let gate { await gate.wait() }
                return behaviour["result"]
            }
        }
        let fixedInitialState = scenario["initialState"].objectValue
        runtime = Runtime(
            initialState: fixedInitialState ?? spec.state.objectValue ?? [:],
            handlers: handlers,
            navigate: { [unowned self] path in log.append(["event": "navigate", "path": path]) },
            validationFunctions: Fixtures.validationFunctions,
            functions: scenario["functions"] == false ? [:] : Fixtures.computedFunctions,
            directives: scenario["directives"] == false ? [] : Fixtures.directiveDefinitions,
            onStateChange: { [unowned self] changes in
                log.append(["event": "stateChange", "changes": .array(JSONArray(changes.map { ["path": .string($0.path), "value": normalised($0.value)] }))])
            }
        )
        let unobserve = ActionObservers.register(ActionObserver(
            onDispatch: { [unowned self] event in
                var entry: JSONObject = ["event": "dispatch", "name": event.name]
                if let params = event.params { entry["params"] = normalised(.object(params)) }
                log.append(.object(entry))
            },
            onSettle: { [unowned self] event in
                var entry: JSONObject = ["event": "settle", "name": event.name, "ok": .bool(event.ok)]
                if let error = event.error { entry["error"] = Actions.message(of: error) }
                log.append(.object(entry))
            }
        ))
        defer { unobserve() }

        var steps: [JSONValue] = []
        try await messages.record {
            runtime.render(spec, components: components, loading: loading)
            await settle()
        }
        steps.append(record("mount"))
        for step in scenario["steps"].arrayValue ?? [] {
            try await messages.record {
                try await perform(step)
                await settle()
            }
            steps.append(record(step))
        }
        return steps
    }

    /// Settles the runtime, then does what upstream's probe components do
    /// after a commit: register field validation and report render failures.
    private func settle() async {
        await runtime.settle()
        for _ in 0..<10 {
            var changed = false
            for node in runtime.tree?.allNodes ?? [] where node.status == .rendered {
                guard case let .string(type) = node.type else { continue }
                if fieldTypes.contains(type) { registerField(node) }
                let fail: JSONValue = node.props["fail"] ?? .undefined
                if throwingTypes.contains(type), fail.isTruthy {
                    runtime.reportComponentFailure(nodeID: node.id, error: JavaScriptError.error("\(type) failed to render"))
                    changed = true
                }
            }
            if !changed { break }
            await runtime.settle()
        }
    }

    /// Upstream's probe registers validation when `value` is bound and the
    /// `checks` prop is a non-empty array.
    private func registerField(_ node: RenderNode) {
        guard let path = node.bindings?["value"], !path.isEmpty, case let .array(checks)? = node.props["checks"], !checks.isEmpty else { return }
        var config = JSONObject()
        config["checks"] = .array(checks)
        config["validateOn"] = node.props["validateOn"] ?? JSONValue.undefined
        runtime.validation.registerField(path, config: .object(config))
    }

    private func perform(_ step: JSONValue) async throws {
        if case let .object(emit) = step["emit"] {
            let id = emit["node"]?.stringValue ?? ""
            guard runtime.tree?.allNodes.contains(where: { $0.id == id && $0.status == .rendered }) == true else {
                log.append(["event": "harness", "message": .string("no emit for \(id)")])
                return
            }
            let event = emit["event"]?.stringValue ?? ""
            // Components call emit without awaiting it.
            Task { @MainActor [runtime, weak self] in
                do {
                    try await runtime!.emit(event, nodeID: id)
                } catch {
                    self?.log.append(["event": "rejected", "error": Actions.message(of: error)])
                }
            }
            await Task.yield()
            return
        }
        if case let .object(write) = step["write"] {
            let id = write["node"]?.stringValue ?? ""
            let prop = write["prop"]?.stringValue ?? ""
            if let path = node(id)?.bindings?[prop] {
                runtime.set(path, write["value"] ?? .undefined)
            } else {
                log.append(["event": "harness", "message": .string("no binding \(prop) on \(id)")])
            }
            return
        }
        if case let .object(validate) = step["validate"] {
            let target = node(validate["node"]?.stringValue ?? "")
            var config: JSONObject = ["checks": target?.props["checks"] ?? []]
            config["validateOn"] = target?.props["validateOn"] ?? .undefined
            try runtime.validation.validate(target?.bindings?["value"] ?? "", config: .object(config))
            return
        }
        if case let .object(touch) = step["touch"] {
            runtime.validation.touch(node(touch["node"]?.stringValue ?? "")?.bindings?["value"] ?? "")
            return
        }
        if case let .object(set) = step["setState"] {
            runtime.set(set["path"]?.stringValue ?? "", set["value"] ?? .undefined)
            return
        }
        if case let .object(updates) = step["update"] {
            runtime.update(updates)
            return
        }
        if let next = step.objectValue?["spec"] {
            spec = Spec(next.objectValue ?? [:])
            applySpec()
            return
        }
        if case let .array(patches) = step["patches"] {
            var next = spec
            for patch in patches { try next.apply(JSONPatch(patch.objectValue ?? [:])) }
            spec = next
            applySpec()
            return
        }
        if case let .bool(isLoading) = step["loading"] {
            loading = isLoading
            runtime.render(spec, components: components, loading: loading)
            return
        }
        if step["confirm"] == true { runtime.confirm(); return }
        if step["cancel"] == true { runtime.cancel(); return }
        if case let .string(name) = step["release"] {
            await gates[name]?.open()
            return
        }
        if case let .object(binding) = step["execute"] {
            Task { @MainActor [runtime, weak self] in
                do {
                    try await runtime!.execute(ActionBinding(binding))
                } catch {
                    self?.log.append(["event": "rejected", "error": Actions.message(of: error)])
                }
            }
            await Task.yield()
            return
        }
        Issue.record("unknown step \(step)")
    }

    /// Re-renders with a new spec, then syncs the provider's initial state
    /// from it, as JSONUIProvider does in an effect.
    private func applySpec() {
        runtime.render(spec, components: components, loading: loading)
        if scenario["initialState"].isUndefined {
            runtime.setInitialState(spec.state.objectValue ?? JSONObject())
        }
    }

    private func node(_ id: String) -> RenderNode? {
        runtime.tree?.allNodes.first { $0.id == id }
    }

    private func record(_ step: JSONValue) -> JSONValue {
        defer {
            log = []
            messages.reset()
        }
        let tree: JSONValue = if let error = runtime.renderError {
            ["uncaughtError": .string(error)]
        } else {
            runtime.tree.map(encode) ?? .null
        }
        var fieldStates = JSONObject()
        for (path, state) in runtime.validation.fieldStates {
            var entry = JSONObject()
            entry["touched"] = .bool(state.touched)
            entry["validated"] = .bool(state.validated)
            if let result = state.result {
                let checks: [JSONValue] = result.checks.map { check in
                    var object = JSONObject()
                    object["type"] = check.type
                    object["valid"] = .bool(check.valid)
                    object["message"] = check.message
                    return .object(object)
                }
                var encoded = JSONObject()
                encoded["valid"] = .bool(result.valid)
                encoded["errors"] = .array(JSONArray(result.errors))
                encoded["checks"] = .array(JSONArray(checks))
                entry["result"] = .object(encoded)
            } else {
                entry["result"] = .null
            }
            fieldStates[path] = .object(entry)
        }
        var output = JSONObject()
        output["step"] = step
        output["tree"] = tree
        output["state"] = Tagged.encode(normalised(.object(runtime.state)))
        output["log"] = Tagged.encode(.array(JSONArray(log)))
        output["messages"] = messages.dedupedEncoded
        if let pending = runtime.pendingConfirmation {
            output["pendingConfirmation"] = Tagged.encode(normalised(pending.action.confirm))
        } else {
            output["pendingConfirmation"] = .null
        }
        output["fieldStates"] = Tagged.encode(.object(fieldStates))
        return .object(output)
    }

    private func encode(_ node: RenderNode) -> JSONValue {
        var object: JSONObject = ["id": .string(node.id), "key": .string(node.key), "type": Tagged.encode(node.type)]
        if let scope = node.repeatScope {
            object["repeat"] = ["index": .number(Double(scope.index)), "basePath": .string(scope.basePath)]
        }
        object["status"] = .string(node.status.rawValue)
        guard node.status == .rendered else { return .object(object) }
        object["props"] = Tagged.encode(normalised(.object(node.props)))
        if let bindings = node.bindings {
            var encoded = JSONObject()
            for key in node.props.keys where bindings[key] != nil { encoded[key] = .string(bindings[key]!) }
            for (key, path) in bindings where encoded[key] == nil { encoded[key] = .string(path) }
            object["bindings"] = .object(encoded)
        }
        if !node.children.isEmpty { object["children"] = .array(JSONArray(node.children.map(encode))) }
        let slots = node.slots.filter { !$0.nodes.isEmpty }
        if !slots.isEmpty {
            var encoded = JSONObject()
            for slot in slots { encoded[slot.name] = .array(JSONArray(slot.nodes.map(encode))) }
            object["slots"] = .object(encoded)
        }
        return .object(object)
    }
}

/// Replaces generated ids ("<milliseconds>-<counter>") with the placeholder
/// the harness writes, since clocks differ.
func normalised(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .string(string):
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, parts[0].count == 13, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) {
            return "<generated-id>"
        }
        return value
    case let .array(array):
        return .array(JSONArray(array.map(normalised)))
    case let .object(object):
        var out = JSONObject()
        for (key, member) in object { out[key] = normalised(member) }
        return .object(out)
    default:
        return value
    }
}

/// An async gate a pending handler waits on until a "release" step.
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
