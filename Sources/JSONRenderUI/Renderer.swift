import JSONRender
import SwiftUI

/// Draws a spec with a registry's components, like upstream `<Renderer>`
/// inside a `<JSONUIProvider>`. The ``Runtime`` plays the provider: it holds
/// state, actions and validation, and can be shared with other views.
///
/// ```swift
/// @State private var runtime = Runtime(initialState: ["name": "Ada"])
///
/// var body: some View {
///     Renderer(spec: spec, registry: registry, runtime: runtime)
/// }
/// ```
///
/// The renderer asks for confirmation of actions with a `confirm` field. Set
/// `presentsConfirmations` to false on all but one renderer sharing a runtime.
public struct Renderer: View {
    let spec: Spec?
    let registry: Registry
    let runtime: Runtime
    let loading: Bool
    let presentsConfirmations: Bool

    public init(spec: Spec?, registry: Registry, runtime: Runtime, loading: Bool = false, presentsConfirmations: Bool = true) {
        self.spec = spec
        self.registry = registry
        self.runtime = runtime
        self.loading = loading
        self.presentsConfirmations = presentsConfirmations
    }

    private struct Input: Equatable {
        var spec: Spec?
        var registry: AnyHashable
        var loading: Bool
    }

    public var body: some View {
        Group {
            if let tree = runtime.tree {
                NodeView(node: tree, runtime: runtime, registry: registry)
            }
        }
        .environment(runtime)
        .onChange(of: Input(spec: spec, registry: registry.identity, loading: loading), initial: true) {
            runtime.render(spec, components: registry, loading: loading)
        }
        .modifier(ConfirmationPresenter(runtime: runtime, isEnabled: presentsConfirmations))
    }
}

/// Draws one node: its component when it rendered, nothing otherwise.
struct NodeView: View {
    let node: RenderNode
    let runtime: Runtime
    let registry: Registry

    var body: some View {
        if node.status == .rendered, let component = registry.component(for: node.type) {
            ComponentView(component: component, context: ComponentContext(node: node, runtime: runtime, registry: registry))
        }
    }
}

/// Runs a component body and reports a throw to the runtime, which marks the
/// element failed, as a React error boundary does.
struct ComponentView: View {
    let component: Component
    let context: ComponentContext

    var body: some View {
        switch Result(catching: { try component.body(context) }) {
        case let .success(view):
            view
        case let .failure(error):
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear { context.runtime.reportComponentFailure(nodeID: context.node.id, error: error) }
        }
    }
}
