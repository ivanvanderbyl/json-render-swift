/// AI SDK message parts, like upstream `buildSpecFromParts` and
/// `getTextFromParts` from `@json-render/react`.
public enum MessageParts {
    /// Replays every `data-spec` part into a spec, like upstream
    /// `buildSpecFromParts`: `patch` parts apply a JSON Patch, `flat` parts
    /// assign a complete spec's members, and `nested` parts assign the flat
    /// form of a nested spec. Returns `nil` when there are no spec parts.
    /// Throws when a patch's `test` operation fails.
    public static func spec(from parts: [JSONObject]) throws -> Spec? {
        var spec = Spec(root: "", elements: [:])
        var hasSpec = false
        for part in parts where part["type"] == .string(SpecDataPart.type) {
            guard case let .object(data)? = part["data"] else { continue }
            switch data["type"] {
            case "patch"?:
                guard case let .object(patch)? = data["patch"] else { continue }
                hasSpec = true
                try spec.apply(JSONPatch(patch))
            case "flat"?:
                guard case let .object(flat)? = data["spec"] else { continue }
                hasSpec = true
                for (key, value) in flat { spec.object[key] = value }
            case "nested"?:
                guard case let .object(nested)? = data["spec"] else { continue }
                hasSpec = true
                for (key, value) in Spec(nested: nested).object { spec.object[key] = value }
            default:
                continue
            }
        }
        return hasSpec ? spec : nil
    }

    /// Joins the trimmed text of every `text` part with blank lines, like
    /// upstream `getTextFromParts`.
    public static func text(from parts: [JSONObject]) -> String {
        parts.compactMap { part -> String? in
            guard part["type"] == "text", case let .string(text)? = part["text"] else { return nil }
            let trimmed = JavaScript.trim(text)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n\n")
    }
}

extension Spec {
    /// Builds a spec from elements that name their parent with `parentKey`,
    /// like upstream `flatToTree`. The element without a parent is the root.
    public init(flatElements: [JSONObject]) {
        var elements = JSONObject()
        var root = ""
        for element in flatElements {
            let key = (element["key"] ?? .undefined).javaScriptString
            elements[key] = [
                "type": element["type"] ?? .undefined,
                "props": element["props"] ?? .undefined,
                "children": [],
                "visible": element["visible"] ?? .undefined,
            ]
        }
        for element in flatElements {
            let key = (element["key"] ?? .undefined).javaScriptString
            let parentKey = element["parentKey"] ?? .undefined
            if parentKey.isTruthy {
                let parent = parentKey.javaScriptString
                guard case var .object(parentElement)? = elements[parent] else { continue }
                var children = parentElement["children"]?.arrayValue ?? []
                children.append(.string(key))
                parentElement["children"] = .array(children)
                elements[parent] = .object(parentElement)
            } else {
                root = key
            }
        }
        self.init(root: root, elements: elements)
    }
}
