/// One element instance in a rendered spec, like one upstream
/// `ElementRenderer`. The SwiftUI renderer draws this tree.
public struct RenderNode: Sendable, Identifiable, Equatable {
    public enum Status: String, Sendable {
        /// The element rendered with a component.
        case rendered
        /// The element's `visible` condition is false.
        case hidden
        /// No component is registered for the type and there is no fallback.
        case noRenderer
        /// An error boundary caught an error rendering the element or a descendant.
        case failed
    }

    /// The scope of a node inside a `repeat`, like upstream `RepeatScopeValue`.
    public struct RepeatScope: Sendable, Equatable {
        public var item: JSONValue
        public var index: Int
        public var basePath: String
    }

    public struct Slot: Sendable, Equatable {
        public var name: String
        public var nodes: [RenderNode]
    }

    /// A path of element keys, slot names and repeat keys that identifies the
    /// instance, such as "list/[item-1]/title".
    public var id: String
    /// The element's key in the spec.
    public var key: String
    /// The element's `type`.
    public var type: JSONValue
    public var status: Status
    /// The element with its props resolved, when rendered.
    public var element: UIElement
    /// The resolved props, when rendered.
    public var props: JSONObject
    /// Prop name to state path, for props using `$bindState` or `$bindItem`.
    public var bindings: [String: String]?
    /// The nearest repeat scope, if the node is inside a repeat.
    public var repeatScope: RepeatScope?
    public var children: [RenderNode]
    public var slots: [Slot]
    /// Whether the spec is still streaming.
    public var loading: Bool
}

extension RenderNode {
    /// This node and every node below it, depth first, children before slots.
    public var allNodes: [RenderNode] {
        [self] + children.flatMap(\.allNodes) + slots.flatMap { $0.nodes.flatMap(\.allNodes) }
    }

    /// The node with an id, searching this node and its descendants.
    public func node(id: String) -> RenderNode? {
        if self.id == id { return self }
        for child in children { if let found = child.node(id: id) { return found } }
        for slot in slots { for child in slot.nodes { if let found = child.node(id: id) { return found } } }
        return nil
    }
}

/// What the runtime needs to know about the component registry, like upstream
/// `registry` and `fallback`.
public protocol ComponentLookup {
    /// True when a component is registered for the type.
    func hasComponent(_ type: String) -> Bool
    /// True when a fallback renders unknown types.
    var hasFallback: Bool { get }
    /// The slots a catalog declares for the type, when the registry came from a catalog.
    func declaredSlots(for type: String) -> [String]?
    /// Changes when the registry changes, so the runtime re-renders every
    /// element, as upstream does when the `registry` prop changes.
    var identity: AnyHashable { get }
}

/// A registry described by type names, for UI-free use and tests.
public struct ComponentTypes: ComponentLookup, Sendable, Hashable {
    public var types: Set<String>
    public var hasFallback: Bool
    public var slots: [String: [String]]?

    public init(_ types: [String], fallback: Bool = false, slots: [String: [String]]? = nil) {
        self.types = Set(types)
        hasFallback = fallback
        self.slots = slots
    }

    public func hasComponent(_ type: String) -> Bool { types.contains(type) }
    public func declaredSlots(for type: String) -> [String]? { slots?[type] }
    public var identity: AnyHashable { AnyHashable(self) }
}
