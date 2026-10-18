#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import JSONRender
import SwiftUI
import Testing
@testable import JSONRenderUI

// Tests the SwiftUI layer by hosting views (see Host): laying the
// view out evaluates every body, so a recording component sees exactly what
// the renderer draws. Behaviour of the render tree itself is covered by the
// UI-free JSONRenderTests and the conformance suites.

/// Draws a view and lays it out so every body runs: an NSHostingView on
/// macOS, and a UIHostingController in a window on iOS.
@MainActor
final class Host<Content: View> {
    #if canImport(UIKit)
    let controller: UIHostingController<Content>
    let window: UIWindow

    init(_ content: Content, width: CGFloat = 400, height: CGFloat = 800) {
        controller = UIHostingController(rootView: content)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        layout()
    }

    func update(_ content: Content) {
        controller.rootView = content
        layout()
    }

    func layout() {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
    #else
    let view: NSHostingView<Content>

    init(_ content: Content, width: CGFloat = 400, height: CGFloat = 800) {
        view = NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
    }

    func update(_ content: Content) {
        view.rootView = content
        layout()
    }

    func layout() { view.layoutSubtreeIfNeeded() }
    #endif
}

/// Diagnostics a test receives.
final class Warnings: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ text: String) { lock.withLock { stored.append(text) } }
    var texts: [String] { lock.withLock { stored } }
}

/// Records each component body the renderer evaluates.
@MainActor
final class DrawLog {
    struct Draw {
        var type: String
        var nodeID: String
        var props: JSONObject
    }

    var draws: [Draw] = []
    var contexts: [String: ComponentContext] = [:]

    /// A component that records its draw, then draws its children and slots.
    func component(_ type: String) -> Component {
        Component { [unowned self] context in
            let _ = record(type, context)
            VStack {
                ForEach(context.slots.keys.sorted(), id: \.self) { name in context.slots[name] }
                context.children
            }
        }
    }

    func record(_ type: String, _ context: ComponentContext) {
        draws.append(Draw(type: type, nodeID: context.node.id, props: context.props))
        contexts[context.node.id] = context
    }

    func reset() { draws = [] }

    /// The `text` prop of each drawn component, in draw order.
    var texts: [String] { draws.compactMap { $0.props["text"]?.stringValue } }
}

@MainActor
@Suite("Renderer view")
struct RendererViewTests {
    // Ports upstream packages/react/src/renderer.test.tsx › "renders named slots
    // through defineRegistry", drawn by SwiftUI.
    @Test("renders named slots through defineRegistry")
    func rendersNamedSlotsThroughRegistry() throws {
        let catalog = Catalog(schema: .react, components: [
            "Layout": ComponentDefinition(props: try JSONSchema(["type": "object", "properties": [:]]), slots: ["default", "header", "footer"]),
            "Text": ComponentDefinition(props: try JSONSchema(["type": "object", "properties": ["text": ["type": "string"]]]), slots: []),
        ])
        let log = DrawLog()
        let registry = Registry(catalog: catalog, components: [
            "Layout": Component { context in
                VStack {
                    context.slot("header")
                    context.children
                    context.slot("footer")
                }
            },
            "Text": Component { context in
                let _ = log.record("Text", context)
                Text(context.props["text"]?.stringValue ?? "")
            },
        ])
        let spec = Spec(root: "layout", elements: [
            "layout": ["type": "Layout", "props": [:], "children": ["main"], "slots": ["header": ["header"], "footer": ["footer"]]],
            "header": ["type": "Text", "props": ["text": "Header"]],
            "main": ["type": "Text", "props": ["text": "Main"]],
            "footer": ["type": "Text", "props": ["text": "Footer"]],
        ])
        let runtime = Runtime()
        _ = Host(Renderer(spec: spec, registry: registry, runtime: runtime))
        #expect(log.texts == ["Header", "Main", "Footer"])
    }

    // Ports upstream renderer.test.tsx › "renders null for null spec" and
    // "renders null for spec without root".
    @Test("draws nothing without a spec or root", arguments: [nil, Spec(root: "", elements: [:])])
    func drawsNothingWithoutSpecOrRoot(_ spec: Spec?) {
        let log = DrawLog()
        let registry = Registry(components: ["Text": log.component("Text")])
        _ = Host(Renderer(spec: spec, registry: registry, runtime: Runtime()))
        #expect(log.draws.isEmpty)
    }

    // Ports upstream renderer.test.tsx › "accepts fallback prop".
    @Test("draws unknown types with the fallback")
    func drawsUnknownTypesWithFallback() {
        let log = DrawLog()
        let registry = Registry(components: [:], fallback: log.component("Fallback"))
        let spec = Spec(root: "x", elements: ["x": ["type": "Unknown", "props": ["text": "?"]]])
        _ = Host(Renderer(spec: spec, registry: registry, runtime: Runtime()))
        #expect(log.draws.map(\.type) == ["Fallback"])
        #expect(log.draws.map(\.nodeID) == ["x"])
    }

    @Test("draws visible children in order with resolved props")
    func drawsVisibleChildren() {
        let log = DrawLog()
        let registry = Registry(components: ["Stack": log.component("Stack"), "Text": log.component("Text")])
        let spec = Spec([
            "root": "stack",
            "state": ["name": "Ada", "items": [["label": "one"], ["label": "two"]]],
            "elements": [
                "stack": ["type": "Stack", "props": [:], "children": ["greeting", "hidden", "list"]],
                "greeting": ["type": "Text", "props": ["text": ["$template": "Hi ${/name}"]]],
                "hidden": ["type": "Text", "props": ["text": "never"], "visible": false],
                "list": ["type": "Stack", "props": [:], "repeat": ["statePath": "/items"], "children": ["item"]],
                "item": ["type": "Text", "props": ["text": ["$item": "label"]]],
            ],
        ])
        let runtime = Runtime(initialState: spec.state.objectValue ?? [:])
        _ = Host(Renderer(spec: spec, registry: registry, runtime: runtime))
        #expect(log.texts == ["Hi Ada", "one", "two"])
    }

    @Test("redraws when state changes and when the spec changes")
    func redrawsOnStateAndSpecChanges() async {
        let log = DrawLog()
        let registry = Registry(components: ["Text": log.component("Text")])
        let first = Spec(root: "t", elements: ["t": ["type": "Text", "props": ["text": ["$state": "/name"]]]])
        let runtime = Runtime(initialState: ["name": "Ada"])
        let host = Host(Renderer(spec: first, registry: registry, runtime: runtime))
        #expect(log.texts == ["Ada"])

        log.reset()
        runtime.set("/name", "Grace")
        await runtime.settle()
        host.layout()
        #expect(log.texts == ["Grace"])

        log.reset()
        let second = Spec(root: "t", elements: ["t": ["type": "Text", "props": ["text": "Static"]]])
        host.update(Renderer(spec: second, registry: registry, runtime: runtime))
        #expect(log.texts == ["Static"])
    }

    @Test("a component that throws is reported and drawn as failed")
    func throwingComponentIsReported() async throws {
        struct Broken: Error, CustomStringConvertible { var description: String { "broken" } }
        let log = DrawLog()
        let registry = Registry(components: [
            "Stack": log.component("Stack"),
            "Text": log.component("Text"),
            "Broken": Component { _ in
                throw Broken()
                Text("unreachable")
            },
        ])
        let spec = Spec(root: "stack", elements: [
            "stack": ["type": "Stack", "props": [:], "children": ["bad", "good"]],
            "bad": ["type": "Broken", "props": [:]],
            "good": ["type": "Text", "props": ["text": "fine"]],
        ])
        let runtime = Runtime()
        let host = Host(Renderer(spec: spec, registry: registry, runtime: runtime))
        await runtime.settle()
        host.layout()
        #expect(runtime.tree?.node(id: "stack/bad")?.status == .failed)
        #expect(runtime.tree?.node(id: "stack/good")?.status == .rendered)
    }
}

@MainActor
@Suite("Component context")
struct ComponentContextTests {
    private func render(_ spec: Spec, runtime: Runtime) -> DrawLog {
        let log = DrawLog()
        let registry = Registry(components: ["Input": log.component("Input"), "Button": log.component("Button")])
        _ = Host(Renderer(spec: spec, registry: registry, runtime: runtime))
        return log
    }

    @Test("emit runs the actions bound to the event")
    func emitRunsBoundActions() async throws {
        var calls: [JSONObject] = []
        let runtime = Runtime(handlers: ["save": { params in calls.append(params); return .undefined }])
        let spec = Spec(root: "b", elements: [
            "b": ["type": "Button", "props": [:], "on": ["press": ["action": "save", "params": ["id": 7]]]],
        ])
        let log = render(spec, runtime: runtime)
        let context = try #require(log.contexts["b"])
        context.emit("press")
        context.emit("unbound")
        await runtime.settle()
        #expect(calls == [["id": 7]])
    }

    @Test("on describes the event's bindings")
    func onDescribesBindings() throws {
        let runtime = Runtime()
        let spec = Spec(root: "b", elements: [
            "b": ["type": "Button", "props": [:], "on": ["press": [["action": "a"], ["action": "b", "preventDefault": true]]]],
        ])
        let context = try #require(render(spec, runtime: runtime).contexts["b"])
        #expect(context.on("press").bound)
        #expect(context.on("press").shouldPreventDefault)
        #expect(!context.on("submit").bound)
    }

    @Test("a bound prop writes back to its state path")
    func boundPropWritesBack() async throws {
        let runtime = Runtime(initialState: ["form": ["name": "Ada"]])
        let spec = Spec(root: "i", elements: [
            "i": ["type": "Input", "props": ["value": ["$bindState": "/form/name"], "label": "Name"]],
        ])
        let log = render(spec, runtime: runtime)
        let context = try #require(log.contexts["i"])
        let value = context.binding("value")
        #expect(value.wrappedValue == "Ada")
        value.wrappedValue = "Grace"
        #expect(runtime.get("/form/name") == "Grace")

        // An unbound prop reads its value and ignores writes, like useBoundProp.
        let label = context.binding("label")
        label.wrappedValue = "Changed"
        #expect(label.wrappedValue == "Name")
        #expect(runtime.state == ["form": ["name": "Grace"]])
    }
}

@MainActor
@Suite("Registry")
struct RegistryTests {
    @Test("looks up components, the fallback and catalog slots")
    func looksUpComponents() {
        let catalog = Catalog(schema: .react, components: [
            "Card": ComponentDefinition(slots: ["default", "header"]),
            "Text": ComponentDefinition(),
        ])
        let registry = Registry(catalog: catalog, components: ["Card": Component { _ in EmptyView() }])
        #expect(registry.hasComponent("Card"))
        #expect(!registry.hasComponent("Text"))
        #expect(!registry.hasFallback)
        #expect(registry.declaredSlots(for: "Card") == ["default", "header"])
        #expect(registry.declaredSlots(for: "Text") == nil)
        #expect(Registry(components: [:], fallback: Component { _ in EmptyView() }).hasFallback)
    }

    @Test("a copy keeps its identity and a new registry gets a new one")
    func identity() {
        let registry = Registry(components: [:])
        let copy = registry
        #expect(copy.identity == registry.identity)
        #expect(Registry(components: [:]).identity != registry.identity)
    }

    // Ports the handler wiring of upstream defineRegistry: each action gets its
    // params, the setter and the state, and the setter applies an updater.
    @Test("handlers pass params, setState and state to actions")
    func handlersPassParamsAndState() async throws {
        var seen: [(JSONObject?, JSONObject)] = []
        let registry = Registry(components: [:], actions: [
            "rename": { params, setState, state in
                seen.append((params, state))
                setState { previous in
                    var next = previous
                    next["name"] = params?["to"] ?? .undefined
                    next["count"] = nil
                    return next
                }
            },
        ])
        let runtime = Runtime(initialState: ["name": "Ada", "count": 1])
        let handlers = registry.handlers(for: runtime)
        _ = try await handlers["rename"]?(["to": "Grace"])
        #expect(seen.map(\.0) == [["to": "Grace"]])
        #expect(seen.map(\.1) == [["name": "Ada", "count": 1]])
        #expect(runtime.get("/name") == "Grace")
        #expect(runtime.get("/count") == .undefined)
    }

    // Ports upstream defineRegistry's executeAction.
    @Test("executeAction runs a named action and warns about unknown ones")
    func executeActionRunsNamedActions() async throws {
        var ran: [JSONObject?] = []
        let registry = Registry(components: [:], actions: ["go": { params, _, _ in ran.append(params) }])
        let warnings = Warnings()
        try await Diagnostics.$handler.withValue({ warnings.append($0.text) }) {
            try await registry.executeAction("go", params: ["x": 1], setState: { _ in })
            try await registry.executeAction("missing", params: nil, setState: { _ in })
        }
        #expect(ran == [["x": 1]])
        #expect(warnings.texts == ["Unknown action: missing"])
    }
}

@MainActor
@Suite("Confirm dialog")
struct ConfirmDialogTests {
    @Test("shows the confirm text with upstream's default labels")
    func showsConfirmText() {
        let dialog = ConfirmDialogContent(["title": "Delete?", "message": "Gone for good", "variant": "danger"])
        #expect(dialog.title == "Delete?")
        #expect(dialog.message == "Gone for good")
        #expect(dialog.confirmLabel == "Confirm")
        #expect(dialog.cancelLabel == "Cancel")
        #expect(dialog.isDestructive)

        let custom = ConfirmDialogContent(["title": "Send", "message": "", "confirmLabel": "Send it", "cancelLabel": "Wait"])
        #expect(custom.confirmLabel == "Send it")
        #expect(custom.cancelLabel == "Wait")
        #expect(!custom.isDestructive)
    }
}
