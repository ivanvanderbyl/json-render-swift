import JSONRender
import SwiftUI

/// What a component gets to draw one element, like upstream
/// `ComponentRenderProps` and `ComponentContext`.
@MainActor
public struct ComponentContext {
    /// The element's node in the render tree.
    public let node: RenderNode
    /// The runtime drawing the element: state, actions and validation.
    public let runtime: Runtime
    let registry: Registry

    init(node: RenderNode, runtime: Runtime, registry: Registry) {
        self.node = node
        self.runtime = runtime
        self.registry = registry
    }

    /// The element with resolved props.
    public var element: UIElement { node.element }
    /// The resolved props.
    public var props: JSONObject { node.props }
    /// Prop name to state path for props bound with `$bindState` or
    /// `$bindItem`, like upstream `bindings`.
    public var bindings: [String: String]? { node.bindings }
    /// Whether the spec is still streaming.
    public var loading: Bool { node.loading }

    /// The element's children, drawn in order.
    public var children: Children { Children(nodes: node.children, runtime: runtime, registry: registry) }

    /// The element's named slots, like upstream `slots`.
    public var slots: [String: Children] {
        Dictionary(node.slots.map { ($0.name, Children(nodes: $0.nodes, runtime: runtime, registry: registry)) }) { $1 }
    }

    /// One named slot, or nil when the element does not fill it.
    public func slot(_ name: String) -> Children? { slots[name] }

    /// Runs the actions bound to an event, like upstream `emit(event)`.
    public func emit(_ event: String) {
        runtime.fire(event, nodeID: node.id)
    }

    /// The event's handle, like upstream `on(event)`.
    public func on(_ event: String) -> EventHandle {
        runtime.eventHandle(event, nodeID: node.id)
    }

    /// A prop's value with a setter that writes to the prop's bound state
    /// path, like upstream `useBoundProp`. When the prop is not bound, writes
    /// do nothing.
    public func binding(_ prop: String) -> Binding<JSONValue> {
        let value = props[prop] ?? .undefined
        let path = bindings?[prop]
        let runtime = runtime
        return Binding(
            get: { value },
            set: { newValue in
                if let path { runtime.set(path, newValue) }
            }
        )
    }

    /// True when the element binds an action to the event.
    public func isBound(_ event: String) -> Bool {
        (element["on"])[event].isTruthy
    }
}

/// Draws a list of nodes, such as an element's children or a slot.
public struct Children: View {
    public let nodes: [RenderNode]
    let runtime: Runtime
    let registry: Registry

    init(nodes: [RenderNode], runtime: Runtime, registry: Registry) {
        self.nodes = nodes
        self.runtime = runtime
        self.registry = registry
    }

    public var isEmpty: Bool { nodes.isEmpty }

    public var body: some View {
        ForEach(nodes) { node in
            NodeView(node: node, runtime: runtime, registry: registry)
        }
    }
}
