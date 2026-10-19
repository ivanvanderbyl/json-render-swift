import JSONRender
@testable import JSONRenderStandard
@testable import JSONRenderUI

/// Records the actions a component's events run.
@MainActor
final class ActionLog {
    private(set) var calls: [(action: String, params: JSONObject)] = []

    func handler(_ name: String) -> ActionHandler {
        { [unowned self] params in
            calls.append((name, params))
            return .undefined
        }
    }

    var actions: [String] { calls.map(\.action) }
}

/// One standard component rendered by the runtime, with its context.
@MainActor
struct Rendered {
    let runtime: Runtime
    let log: ActionLog
    let context: ComponentContext
}

/// Renders a single element of a standard component type and returns the
/// context its component gets. Events can bind to the actions "press",
/// "longPress", "remove" and "submit", which the log records.
@MainActor
func render(_ type: String, _ props: JSONObject, on: JSONObject? = nil, state: JSONObject = [:]) throws -> Rendered {
    let log = ActionLog()
    var handlers: [String: ActionHandler] = [:]
    for name in ["press", "longPress", "remove", "submit", "change"] { handlers[name] = log.handler(name) }
    let runtime = Runtime(initialState: state, handlers: handlers)
    var element: JSONObject = ["type": .string(type), "props": .object(props), "children": []]
    if let on { element["on"] = .object(on) }
    let registry = Registry.standard
    runtime.render(Spec(root: "element", elements: ["element": .object(element)]), components: registry)
    guard let node = runtime.tree, node.status == .rendered else { throw RenderFailure() }
    return Rendered(runtime: runtime, log: log, context: ComponentContext(node: node, runtime: runtime, registry: registry))
}

struct RenderFailure: Error {}

/// Binds every event in the list to the action of the same name.
func events(_ names: String...) -> JSONObject {
    var on = JSONObject()
    for name in names { on[name] = ["action": .string(name)] }
    return on
}

extension CSSColor {
    /// A colour from a string the tests know is valid.
    static func css(_ text: String) -> CSSColor { CSSColor(text)! }
}
