/// One mounted element instance from the latest render, like one upstream
/// `ReactiveElementRenderer`.
struct ElementInstance {
    var id: String
    var key: String
    var element: JSONValue
    var context: ResolutionContext
    var signature: Int
    var epoch: Int
    var componentsEpoch: Int
    var loading: Bool
    var scopeToken: Int
    /// The watch effect's dependencies when this instance rendered.
    var effectKey: [Int]
    var node: RenderNode
}

/// The repeat scope an element renders in, with a token that changes each
/// time the owning repeat re-renders (upstream creates a new context value).
struct ScopeFrame {
    var scope: RenderNode.RepeatScope
    var token: Int
}

extension Runtime {
    // MARK: Entry points

    /// Renders a spec, like upstream `<Renderer spec registry loading fallback>`.
    /// Call again whenever the spec, registry or loading flag changes.
    public func render(_ spec: Spec?, components: some ComponentLookup, loading: Bool = false) {
        if self.loading != loading { self.loading = loading }
        self.spec = spec
        self.components = components
        if componentsIdentity != components.identity {
            componentsIdentity = components.identity
            componentsEpoch += 1
        }
        renderNow()
        drain()
    }

    /// Records that a component failed to render, like a React error boundary
    /// catching a component's throw. The element shows as failed until its
    /// signature changes, for example after a corrective patch.
    public func reportComponentFailure(nodeID: String, error: any Error) {
        guard let instance = instances[nodeID] else { return }
        Diagnostics.error("[json-render] Rendering error in <\(instance.node.type.javaScriptString)>: \(Actions.message(of: error).javaScriptString)")
        boundaryErrors[nodeID] = instance.signature
        // Re-render only this element so the boundary takes effect.
        forcedRenders.insert(nodeID)
        renderNow()
        drain()
    }

    // MARK: Rendering

    func renderNow() {
        renderScheduled = false
        progress += 1
        let previous = instances
        var pass = RenderPass(runtime: self, previous: previous)
        var newTree: RenderNode?
        var error: String?
        do {
            newTree = try pass.renderRoot()
        } catch let thrown {
            error = Actions.message(of: thrown).javaScriptString
        }
        // An error outside every boundary unmounts the whole tree upstream.
        instances = error == nil ? pass.mounted : [:]
        forcedRenders = []
        if renderError != error { renderError = error }
        if tree != newTree { tree = newTree }
        for id in boundaryErrors.keys where instances[id] == nil { boundaryErrors[id] = nil }
        runWatchEffects(order: error == nil ? pass.mountOrder : [], previous: previous)
    }
}

/// One render of the spec, like one React render of the element tree.
@MainActor
struct RenderPass {
    let runtime: Runtime
    let previous: [String: ElementInstance]
    var mounted: [String: ElementInstance] = [:]
    /// Mounted ids in completion order: children before parents.
    var mountOrder: [String] = []
    var signatures: [String: Int] = [:]
    var elements = JSONObject()
    /// Element keys from the root to the element being rendered.
    var ancestors: [String] = []

    init(runtime: Runtime, previous: [String: ElementInstance]) {
        self.runtime = runtime
        self.previous = previous
    }

    mutating func renderRoot() throws -> RenderNode? {
        guard let spec = runtime.spec else { return nil }
        // Upstream computes signatures before checking the root.
        let elementsValue = spec.object["elements"] ?? .undefined
        if case let .object(object) = elementsValue {
            elements = object
        } else if elementsValue.isNullish {
            throw JavaScriptError.typeError("Cannot convert undefined or null to object")
        }
        signatures = try runtime.signatures.update(elements)
        guard spec.root.isTruthy else { return nil }
        let rootKey = spec.root.javaScriptString
        let rootElement = elements[rootKey] ?? .undefined
        guard rootElement.isTruthy else { return nil }
        return try renderElement(rootElement, key: rootKey, id: rootKey, scope: nil)
    }

    private func warn(_ message: String) { Diagnostics.warn(message) }

    mutating func renderElement(_ element: JSONValue, key: String, id: String, scope: ScopeFrame?) throws -> RenderNode {
        // Upstream renders a cycle until it runs out of memory. Here the
        // repeated element throws, so the element that reached it fails.
        if ancestors.contains(key) {
            throw JavaScriptError.error("Element \"\(key)\" is its own ancestor, so the spec has a cycle")
        }
        ancestors.append(key)
        defer { ancestors.removeLast() }
        let signature = signatures[key] ?? 0
        if let reused = reuse(id: id, signature: signature, scope: scope) { return reused }

        let context = ResolutionContext(
            state: .object(runtime.state),
            repeatItem: scope?.scope.item ?? .undefined,
            repeatIndex: scope?.scope.index,
            repeatBasePath: scope?.scope.basePath,
            functions: runtime.storedFunctions,
            directives: runtime.directiveRegistry
        )
        let repeatField = try JavaScript.member("repeat", of: element)
        let visibleField = try JavaScript.member("visible", of: element)
        // A repeat container's $item/$index condition filters its items.
        let split = !repeatField.isUndefined && scope == nil
            ? try Visibility.splitRepeatVisibility(visibleField)
            : (container: visibleField, itemFilter: JSONValue.undefined)
        let isVisible = split.container.isUndefined ? true : try Visibility.evaluate(split.container, in: context)
        let type = try JavaScript.member("type", of: element)

        var node = RenderNode(
            id: id, key: key, type: type, status: .hidden,
            element: UIElement(element.objectValue ?? [:]), props: [:], bindings: nil,
            repeatScope: scope?.scope, children: [], slots: [], loading: runtime.loading
        )
        guard isVisible else { return mount(node, element: element, context: context, signature: signature, scope: scope) }

        // Props resolve before the component is looked up.
        let rawProps = try JavaScript.member("props", of: element)
        var propObject = JSONObject()
        if !rawProps.isNullish { for (name, value) in try JavaScript.entries(rawProps) { propObject[name] = value } }
        node.bindings = PropExpression.bindings(for: propObject, in: context)
        node.props = try PropExpression.resolveProps(propObject, in: context)
        var resolvedElement = element.objectValue.map(JSONObject.init(copying:)) ?? JSONObject()
        resolvedElement["props"] = .object(node.props)
        node.element = UIElement(resolvedElement)

        let typeName = type.javaScriptString
        guard let components = runtime.components, components.hasComponent(typeName) || components.hasFallback else {
            warn("No renderer for component type: \(typeName)")
            node.status = .noRenderer
            return mount(node, element: element, context: context, signature: signature, scope: scope)
        }

        let slotsField = try JavaScript.member("slots", of: element)
        if slotsField.isTruthy, let available = components.declaredSlots(for: typeName) {
            for (slotName, _) in try JavaScript.entries(slotsField) {
                if slotName == "default" {
                    warn("[json-render] Component \"\(typeName)\" uses slots.default. Use \"children\" for default slot content.")
                } else if !available.contains(slotName) {
                    warn("[json-render] Unknown slot \"\(slotName)\" on component \"\(typeName)\". Available slots: \(available.joined(separator: ", "))")
                }
            }
        }

        // Child and slot lookups happen in this element's own render.
        let childrenField = try JavaScript.member("children", of: element)
        var plannedChildren: [(String, JSONValue)] = []
        if !repeatField.isTruthy, childrenField.isTruthy {
            plannedChildren = try plan(childrenField, method: "resolvedElement.children.map", owner: typeName, slot: nil)
        }
        var plannedSlots: [(String, [(String, JSONValue)])] = []
        if slotsField.isTruthy {
            for (slotName, childKeys) in try JavaScript.entries(slotsField) {
                plannedSlots.append((slotName, try plan(childKeys, method: "childKeys.map", owner: typeName, slot: slotName)))
            }
        }

        node.status = .rendered
        if runtime.boundaryErrors[id] == signature {
            node.status = .failed
            return mount(node, element: element, context: context, signature: signature, scope: scope)
        }
        do {
            if repeatField.isTruthy {
                node.children = try renderRepeat(repeatField, element: element, owner: typeName, ownerID: id, itemFilter: split.itemFilter, scope: scope)
            } else {
                node.children = try plannedChildren.map { childKey, child in
                    try renderElement(child, key: childKey, id: "\(id)/\(childKey)", scope: scope)
                }
            }
            node.slots = try plannedSlots.map { slotName, children in
                RenderNode.Slot(name: slotName, nodes: try children.map { childKey, child in
                    try renderElement(child, key: childKey, id: "\(id)/@\(slotName)/\(childKey)", scope: scope)
                })
            }
        } catch {
            Diagnostics.error("[json-render] Rendering error in <\(typeName)>: \(Actions.message(of: error).javaScriptString)")
            runtime.boundaryErrors[id] = signature
            mounted = mounted.filter { !$0.key.hasPrefix(id + "/") }
            mountOrder.removeAll { $0.hasPrefix(id + "/") }
            node.status = .failed
            node.children = []
            node.slots = []
        }
        return mount(node, element: element, context: context, signature: signature, scope: scope)
    }

    /// Looks up each child key, warning about missing elements unless loading.
    private func plan(_ keys: JSONValue, method: String, owner: String, slot: String?) throws -> [(String, JSONValue)] {
        guard case let .array(array) = keys else {
            throw JavaScriptError.typeError("\(method) is not a function")
        }
        var planned: [(String, JSONValue)] = []
        for childKey in array {
            let key = childKey.javaScriptString
            let child = elements[key] ?? .undefined
            guard child.isTruthy else {
                if !runtime.loading {
                    let location = slot.map { "in slot \"\($0)\" of \"\(owner)\"" } ?? "as child of \"\(owner)\""
                    warn("[json-render] Missing element \"\(key)\" referenced \(location). This element will not render.")
                }
                continue
            }
            planned.append((key, child))
        }
        return planned
    }

    /// Upstream `RepeatChildren`: the children once per item of a state array.
    private mutating func renderRepeat(
        _ repeatField: JSONValue, element: JSONValue, owner: String, ownerID: String, itemFilter: JSONValue, scope: ScopeFrame?
    ) throws -> [RenderNode] {
        let statePath = try RepeatScope.resolveStatePath(try JavaScript.member("statePath", of: repeatField), base: scope?.scope.basePath)
        guard let statePath else {
            warn("[json-render] $item in repeat.statePath used outside of a repeat scope")
            return []
        }
        let itemsValue = JSONValue.object(runtime.state).value(atPath: statePath)
        let items: JSONArray
        switch itemsValue {
        case .undefined, .null: items = []
        case let .array(array): items = array
        default: throw JavaScriptError.typeError("items.map is not a function")
        }
        let keyField = try JavaScript.member("key", of: repeatField)
        let childrenField = try JavaScript.member("children", of: element)
        var nodes: [RenderNode] = []
        for (index, item) in items.enumerated() {
            if !itemFilter.isUndefined {
                let filterContext = ResolutionContext(state: .object(runtime.state), repeatItem: item, repeatIndex: index)
                if try !Visibility.evaluate(itemFilter, in: filterContext) { continue }
            }
            let itemKey: String
            if keyField.isTruthy, item.isContainer {
                let field = try JavaScript.member(keyField.javaScriptString, of: item)
                itemKey = field.isNullish ? String(index) : field.javaScriptString
            } else {
                itemKey = String(index)
            }
            runtime.scopeTokenCounter += 1
            let frame = ScopeFrame(
                scope: RenderNode.RepeatScope(item: item, index: index, basePath: RepeatScope.itemStatePath(statePath, index: index)),
                token: runtime.scopeTokenCounter
            )
            if childrenField.isNullish { continue }
            guard case let .array(childKeys) = childrenField else {
                throw JavaScriptError.typeError("element.children?.map is not a function")
            }
            for childKey in childKeys {
                let key = childKey.javaScriptString
                let child = elements[key] ?? .undefined
                guard child.isTruthy else {
                    if !runtime.loading {
                        warn("[json-render] Missing element \"\(key)\" referenced as child of \"\(owner)\" (repeat). This element will not render.")
                    }
                    continue
                }
                nodes.append(try renderElement(child, key: key, id: "\(ownerID)/[\(itemKey)]/\(key)", scope: frame))
            }
        }
        return nodes
    }

    /// Reuses the previous render of an element whose inputs are unchanged,
    /// like upstream's memoised ElementRenderer: same signature, loading flag,
    /// registry and repeat scope, and no provider value changed since.
    private mutating func reuse(id: String, signature: Int, scope: ScopeFrame?) -> RenderNode? {
        guard let prior = previous[id],
              prior.signature == signature,
              prior.epoch == runtime.contextEpoch,
              prior.componentsEpoch == runtime.componentsEpoch,
              prior.loading == runtime.loading,
              prior.scopeToken == (scope?.token ?? 0),
              !runtime.forcedRenders.contains(id)
        else { return nil }
        if runtime.forcedRenders.contains(where: { $0.hasPrefix(id + "/") }) {
            return rebuild(prior)
        }
        // The whole subtree stays mounted as it was.
        for (childID, instance) in previous where childID.hasPrefix(id + "/") { mounted[childID] = instance }
        for childID in previousOrder(below: id) { mountOrder.append(childID) }
        mounted[id] = prior
        mountOrder.append(id)
        return prior.node
    }

    /// Keeps an unchanged element but re-renders the descendants that must
    /// update, as React re-renders only the error boundary that caught.
    private mutating func rebuild(_ prior: ElementInstance) -> RenderNode {
        var node = prior.node
        var children: [RenderNode] = []
        for child in node.children { children.append(refresh(child)) }
        node.children = children
        var slots: [RenderNode.Slot] = []
        for slot in node.slots {
            var nodes: [RenderNode] = []
            for child in slot.nodes { nodes.append(refresh(child)) }
            slots.append(RenderNode.Slot(name: slot.name, nodes: nodes))
        }
        node.slots = slots
        var kept = prior
        kept.node = node
        mounted[prior.id] = kept
        mountOrder.append(prior.id)
        return node
    }

    private mutating func refresh(_ child: RenderNode) -> RenderNode {
        guard let instance = previous[child.id] else { return child }
        let forced = runtime.forcedRenders
        if forced.contains(child.id) {
            let scope = child.repeatScope.map { ScopeFrame(scope: $0, token: instance.scopeToken) }
            if let node = try? renderElement(instance.element, key: instance.key, id: child.id, scope: scope) { return node }
            return child
        }
        if forced.contains(where: { $0.hasPrefix(child.id + "/") }) { return rebuild(instance) }
        for (id, kept) in previous where id.hasPrefix(child.id + "/") { mounted[id] = kept }
        for id in previousOrder(below: child.id) { mountOrder.append(id) }
        mounted[child.id] = instance
        mountOrder.append(child.id)
        return child
    }

    private func previousOrder(below id: String) -> [String] {
        runtime.lastMountOrder.filter { $0.hasPrefix(id + "/") }
    }

    private mutating func mount(_ node: RenderNode, element: JSONValue, context: ResolutionContext, signature: Int, scope: ScopeFrame?) -> RenderNode {
        mounted[node.id] = ElementInstance(
            id: node.id, key: node.key, element: element, context: context, signature: signature,
            epoch: runtime.contextEpoch, componentsEpoch: runtime.componentsEpoch, loading: runtime.loading,
            scopeToken: scope?.token ?? 0,
            effectKey: [runtime.stateVersion, runtime.functionsVersion, runtime.directivesVersion, runtime.executeVersion, scope?.token ?? 0],
            node: node
        )
        mountOrder.append(node.id)
        return node
    }
}
