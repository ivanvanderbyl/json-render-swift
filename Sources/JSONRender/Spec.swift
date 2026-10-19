/// A json-render spec: a flat `root` / `elements` / `state` tree.
///
/// `Spec` wraps the plain object a spec is in JavaScript. Upstream code reads
/// specs as untyped objects, so a malformed spec (for example `children` that
/// is not an array) is kept as written and handled the way upstream handles
/// it, rather than being rejected or normalised while decoding.
public struct Spec: Sendable, Equatable {
    /// The underlying plain object.
    public var object: JSONObject

    public init(_ object: JSONObject) { self.object = object }

    public init(root: String, elements: JSONObject, state: JSONObject? = nil) {
        object = ["root": .string(root), "elements": .object(elements)]
        if let state { object["state"] = .object(state) }
    }

    /// Parses a spec from JSON text.
    public init(parsing text: String) throws {
        let value = try JSONValue(parsing: text)
        guard case let .object(object) = value else {
            throw JSONParseError(message: "A spec must be a JSON object", offset: 0)
        }
        self.object = object
    }

    /// The `root` member: normally the key of the root element.
    public var root: JSONValue {
        get { object["root"] ?? .undefined }
        set { object["root"] = newValue }
    }

    /// The `elements` member, or an empty object when it is missing or not an object.
    public var elements: JSONObject {
        get { object["elements"]?.objectValue ?? [:] }
        set { object["elements"] = .object(newValue) }
    }

    /// The `state` member, or `undefined` when the spec has none.
    public var state: JSONValue {
        get { object["state"] ?? .undefined }
        set { object["state"] = newValue }
    }

    /// The element stored under `key`, if any.
    public func element(_ key: String) -> UIElement? {
        guard case let .object(element) = object["elements"]?[key] ?? .undefined else { return nil }
        return UIElement(element)
    }

    /// Applies one JSON Patch operation in place, like upstream `applySpecPatch`.
    public mutating func apply(_ patch: JSONPatch) throws {
        var value = JSONValue.object(object)
        object = [:]
        defer { if case let .object(updated) = value { object = updated } }
        try SpecStream.apply(patch, to: &value)
    }
}

extension Spec {
    /// Converts a nested tree, where each node lists its child nodes inline,
    /// into a flat spec, like upstream `nestedToFlat`. Keys are generated in
    /// visit order as `el-0`, `el-1`, and so on. A `state` object on the root
    /// node moves to the spec; extra fields such as `visible` and `on` stay on
    /// their element.
    public init(nested: JSONObject) {
        var elements = JSONObject()
        var counter = 0

        func walk(_ node: JSONObject) -> String {
            let key = "el-\(counter)"
            counter += 1

            var childKeys: [JSONValue] = []
            if case let .array(children) = node["children"] ?? .undefined {
                for child in children {
                    if case let .object(childNode) = child, childNode.hasKey("type") {
                        childKeys.append(.string(walk(childNode)))
                    }
                }
            }

            var slots = JSONObject()
            if case let .object(rawSlots) = node["slots"] ?? .undefined {
                for (slotName, slotChildren) in rawSlots {
                    guard case let .array(children) = slotChildren else { continue }
                    var keys: [JSONValue] = []
                    for child in children {
                        if case let .object(childNode) = child, childNode.hasKey("type") {
                            keys.append(.string(walk(childNode)))
                        }
                    }
                    slots[slotName] = .array(JSONArray(keys))
                }
            }

            let type = node["type"] ?? .undefined
            let props = node["props"] ?? .undefined
            var element: JSONObject = [
                "type": type.isNullish ? "unknown" : type,
                "props": props.isNullish ? [:] : props,
                "children": .array(JSONArray(childKeys)),
            ]
            if !slots.isEmpty { element["slots"] = .object(slots) }
            for (field, value) in node {
                switch field {
                case "type", "props", "children", "slots", "state": continue
                default: if !value.isUndefined { element[field] = value }
                }
            }
            elements[key] = .object(element)
            return key
        }

        let root = walk(nested)
        object = ["root": .string(root), "elements": .object(elements)]
        if case .object = nested["state"] ?? .undefined {
            object["state"] = nested["state"]
        }
    }
}

/// One element of a spec: `type`, `props`, `children` and the optional
/// `slots`, `visible`, `on`, `repeat` and `watch` fields.
///
/// Like ``Spec``, `UIElement` wraps the element's plain object.
public struct UIElement: Sendable, Equatable {
    public var object: JSONObject

    public init(_ object: JSONObject) { self.object = object }

    public init(
        type: String,
        props: JSONObject = [:],
        children: [String] = [],
        visible: JSONValue = .undefined,
        on: JSONObject? = nil,
        repeat: JSONObject? = nil,
        watch: JSONObject? = nil
    ) {
        object = [
            "type": .string(type),
            "props": .object(props),
            "children": .array(JSONArray(children.map(JSONValue.string))),
        ]
        if !visible.isUndefined { object["visible"] = visible }
        if let on { object["on"] = .object(on) }
        if let `repeat` { object["repeat"] = .object(`repeat`) }
        if let watch { object["watch"] = .object(watch) }
    }

    public subscript(field: String) -> JSONValue {
        get { object[field] ?? .undefined }
        set { object[field] = newValue }
    }

    public var type: JSONValue { self["type"] }
    public var props: JSONValue { self["props"] }
    public var children: JSONValue { self["children"] }
    public var slots: JSONValue { self["slots"] }
    public var visible: JSONValue { self["visible"] }
    public var on: JSONValue { self["on"] }
    public var `repeat`: JSONValue { self["repeat"] }
    public var watch: JSONValue { self["watch"] }
}
