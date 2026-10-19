import Foundation
@testable import JSONRender

/// Helpers for tests that drive the UI-free runtime the way upstream's React
/// tests drive JSONUIProvider and Renderer.
extension RenderNode {
    /// Rendered nodes of a component type, in tree order.
    func rendered(_ type: String) -> [RenderNode] {
        allNodes.filter { $0.status == .rendered && $0.type == .string(type) }
    }

    /// The first node with an element key.
    func node(_ key: String) -> RenderNode? {
        allNodes.first { $0.key == key }
    }

    /// A text prop as upstream test components display it: `String(value)`,
    /// with null and undefined shown as "".
    func text(_ prop: String = "text") -> String {
        let value = props[prop] ?? .undefined
        return value.isNullish ? "" : value.javaScriptString
    }
}

/// A recorder for handler calls, standing in for vi.fn().
@MainActor
final class CallRecorder {
    private(set) var calls: [JSONObject] = []

    func handler(returning result: JSONValue = .undefined) -> ActionHandler {
        { [unowned self] params in
            calls.append(params)
            return result
        }
    }
}

/// Registers form validation for a rendered field node the way upstream's
/// test InputField does with useFieldValidation: only when `value` is bound
/// and the `checks` prop is a non-empty array.
@MainActor
func registerFieldValidation(_ node: RenderNode, in runtime: Runtime) {
    guard let path = node.bindings?["value"], case let .array(checks)? = node.props["checks"], !checks.isEmpty else { return }
    var config: JSONObject = ["checks": .array(checks)]
    if let validateOn = node.props["validateOn"] { config["validateOn"] = validateOn }
    runtime.validation.registerField(path, config: .object(config))
}
