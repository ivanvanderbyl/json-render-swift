/// A structural problem found by ``SpecValidator``, like upstream `SpecIssue`.
public struct SpecIssue: Sendable, Equatable {
    public enum Severity: String, Sendable { case error, warning }

    public var severity: Severity
    public var message: String
    public var elementKey: String?
    /// One of: missing_root, root_not_found, missing_child, invalid_visible,
    /// repeat_without_children, repeat_item_outside_scope,
    /// repeat_state_mismatch, visible_in_props, orphaned_element, empty_spec,
    /// on_in_props, repeat_in_props, watch_in_props.
    public var code: String

    public init(severity: Severity, message: String, elementKey: String? = nil, code: String) {
        self.severity = severity
        self.message = message
        self.elementKey = elementKey
        self.code = code
    }
}

/// The result of ``SpecValidator/validate(_:checkOrphans:)``.
public struct SpecValidationIssues: Sendable, Equatable {
    /// True when there are no errors. Warnings are allowed.
    public var valid: Bool
    public var issues: [SpecIssue]

    public init(valid: Bool, issues: [SpecIssue]) {
        self.valid = valid
        self.issues = issues
    }
}

/// One change ``SpecValidator/autoFix(_:lossy:)`` made, like upstream `SpecFix`.
public struct SpecFix: Sendable, Equatable {
    public var message: String
    /// True when the fix changes what renders, such as pruning a missing child.
    public var lossy: Bool

    public init(message: String, lossy: Bool) {
        self.message = message
        self.lossy = lossy
    }
}

/// Structural spec checks for common generation mistakes, like upstream
/// `spec-validator.ts`.
public enum SpecValidator {
    /// Validates a spec, like upstream `validateSpec`.
    ///
    /// Reports a missing or unknown root, an empty spec, children and slot
    /// entries that reference missing elements, repeat containers without a
    /// template child, relative repeat paths outside a repeat scope, repeat
    /// paths whose sample state is not an array, malformed `visible`
    /// conditions, and `visible`, `on`, `repeat` or `watch` placed inside
    /// `props`. With `checkOrphans`, unreachable elements are warnings.
    ///
    /// Throws the TypeError upstream throws for specs too malformed to walk,
    /// such as an element that is `null`.
    public static func validate(_ spec: Spec, checkOrphans: Bool = false) throws -> SpecValidationIssues {
        var issues: [SpecIssue] = []
        let root = spec.root
        guard root.isTruthy else {
            issues.append(SpecIssue(severity: .error, message: "Spec has no root element defined.", code: "missing_root"))
            return SpecValidationIssues(valid: false, issues: issues)
        }
        let elements = try JavaScript.member("elements", of: .object(spec.object))
        let rootKey = root.javaScriptString
        func element(_ key: String) -> JSONValue { elements.objectValue?[key] ?? .undefined }

        if try !JavaScript.member(rootKey, of: elements).isTruthy {
            issues.append(SpecIssue(
                severity: .error, message: "Root element \"\(rootKey)\" not found in elements map.", code: "root_not_found"
            ))
        }
        let entries = try JavaScript.entries(elements)
        if entries.isEmpty {
            issues.append(SpecIssue(severity: .error, message: "Spec has no elements.", code: "empty_spec"))
            return SpecValidationIssues(valid: false, issues: issues)
        }

        for (key, value) in entries {
            let children = try JavaScript.member("children", of: value)
            if children.isTruthy {
                for child in try JavaScript.iterate(children, expression: "element.children") {
                    let childKey = child.javaScriptString
                    if !element(childKey).isTruthy {
                        issues.append(SpecIssue(
                            severity: .error,
                            message: "Element \"\(key)\" references child \"\(childKey)\" which does not exist in the elements map.",
                            elementKey: key,
                            code: "missing_child"
                        ))
                    }
                }
            }
            let slots = try JavaScript.member("slots", of: value)
            if slots.isTruthy {
                for (slotName, slotChildren) in try JavaScript.entries(slots) {
                    for child in try JavaScript.iterate(slotChildren, expression: "childKeys") {
                        let childKey = child.javaScriptString
                        if !element(childKey).isTruthy {
                            issues.append(SpecIssue(
                                severity: .error,
                                message: "Element \"\(key)\" references child \"\(childKey)\" in slot \"\(slotName)\" which does not exist in the elements map.",
                                elementKey: key,
                                code: "missing_child"
                            ))
                        }
                    }
                }
            }
            let hasRepeat = try !JavaScript.member("repeat", of: value).isUndefined
            let childCount = children.isTruthy ? try JavaScript.length(of: children) : 0
            if hasRepeat, childCount == 0 {
                issues.append(SpecIssue(
                    severity: .error,
                    message: "Element \"\(key)\" has \"repeat\" but no children. The repeated template must be a child element: add a child that renders one item (it may read fields with {\"$item\": \"field\"}).",
                    elementKey: key,
                    code: "repeat_without_children"
                ))
            }
            let visible = try JavaScript.member("visible", of: value)
            if !visible.isUndefined, !Visibility.isValid(visible) {
                issues.append(SpecIssue(
                    severity: .error,
                    message: "Element \"\(key)\" has an invalid \"visible\" condition: \(visible.stringified() ?? "undefined"). Valid forms: true, false, {\"$state\":\"/path\",\"eq\":value}, {\"$item\":\"field\",\"eq\":value}, {\"$index\":true,\"eq\":n}, an array of those (AND), or {\"$and\":[...]} / {\"$or\":[...]}. Use exactly one of $state, $item, or $index per condition object.",
                    elementKey: key,
                    code: "invalid_visible"
                ))
            }
            let props = try JavaScript.member("props", of: value)
            if props.isTruthy {
                for (field, code) in [("visible", "visible_in_props"), ("on", "on_in_props"), ("repeat", "repeat_in_props"), ("watch", "watch_in_props")] {
                    if try JavaScript.hasProperty(field, in: props), !props[field].isUndefined {
                        issues.append(SpecIssue(
                            severity: .error,
                            message: "Element \"\(key)\" has \"\(field)\" inside \"props\". It should be a top-level field on the element (sibling of type/props/children).",
                            elementKey: key,
                            code: code
                        ))
                    }
                }
            }
        }

        // Repeat statePath checks walk the tree so relative paths see their scope.
        var validatedKeys: Set<ExactKey> = []
        var validatedContexts: Set<String> = []
        func validateRepeatPaths(_ key: String, base: String?, sampleAvailable: Bool, ancestors: Set<ExactKey>) throws {
            if ancestors.contains(ExactKey(key)) { return }
            let value = element(key)
            guard value.isTruthy else { return }
            validatedKeys.insert(ExactKey(key))
            let contextKey = "\(key)\u{0}\(base ?? "")\u{0}\(sampleAvailable)"
            if !validatedContexts.insert(contextKey).inserted { return }

            var childBase = base
            var childSample = sampleAvailable
            let repeatValue = try JavaScript.member("repeat", of: value)
            if !repeatValue.isUndefined {
                let rawStatePath = try JavaScript.member("statePath", of: repeatValue)
                let statePath = try RepeatScope.resolveStatePath(rawStatePath, base: base)
                let displayPath = rawStatePath.stringValue ?? rawStatePath.stringified() ?? "undefined"
                if let statePath {
                    let isString = rawStatePath.stringValue != nil
                    let canCheckSample = !spec.state.isUndefined && (isString || sampleAvailable)
                    let sample = canCheckSample ? spec.state.value(atPath: statePath) : .undefined
                    let isArray = sample.arrayValue != nil
                    if canCheckSample, !isArray {
                        let found = sample.isUndefined ? " has no value there" : " has a \(sample.typeOf) there"
                        issues.append(SpecIssue(
                            severity: .error,
                            message: "Element \"\(key)\" repeats over \"\(statePath)\" but state\(found). Repeat statePath must reference an array in state; add sample items to state at that path.",
                            elementKey: key,
                            code: "repeat_state_mismatch"
                        ))
                    }
                    childBase = RepeatScope.itemStatePath(statePath, index: 0)
                    childSample = canCheckSample && isArray && !(sample.arrayValue?.isEmpty ?? true)
                } else {
                    issues.append(SpecIssue(
                        severity: .error,
                        message: "Element \"\(key)\" uses relative repeat statePath \(displayPath) outside a repeat scope.",
                        elementKey: key,
                        code: "repeat_item_outside_scope"
                    ))
                    childBase = nil
                    childSample = false
                }
            }
            var nextAncestors = ancestors
            nextAncestors.insert(ExactKey(key))
            let children = try JavaScript.member("children", of: value)
            for child in children.isNullish ? [] : try JavaScript.iterate(children, expression: "element.children") {
                try validateRepeatPaths(child.javaScriptString, base: childBase, sampleAvailable: childSample, ancestors: nextAncestors)
            }
            let slots = try JavaScript.member("slots", of: value)
            for (_, slotChildren) in slots.isNullish ? [] : try JavaScript.entries(slots) {
                for child in try JavaScript.iterate(slotChildren, expression: "childKeys") {
                    try validateRepeatPaths(child.javaScriptString, base: base, sampleAvailable: sampleAvailable, ancestors: nextAncestors)
                }
            }
        }
        if element(rootKey).isTruthy {
            try validateRepeatPaths(rootKey, base: nil, sampleAvailable: true, ancestors: [])
        }
        for (key, _) in entries where !validatedKeys.contains(ExactKey(key)) {
            try validateRepeatPaths(key, base: nil, sampleAvailable: true, ancestors: [])
        }

        if checkOrphans {
            var reachable: Set<ExactKey> = []
            func walk(_ key: String) {
                if !reachable.insert(ExactKey(key)).inserted { return }
                let value = element(key)
                for child in value["children"].arrayValue ?? [] where element(child.javaScriptString).isTruthy {
                    walk(child.javaScriptString)
                }
                for (_, slotChildren) in value["slots"].objectValue ?? [:] {
                    for child in slotChildren.arrayValue ?? [] where element(child.javaScriptString).isTruthy {
                        walk(child.javaScriptString)
                    }
                }
            }
            if element(rootKey).isTruthy { walk(rootKey) }
            for (key, _) in entries where !reachable.contains(ExactKey(key)) {
                issues.append(SpecIssue(
                    severity: .warning,
                    message: "Element \"\(key)\" is not reachable from root \"\(rootKey)\".",
                    elementKey: key,
                    code: "orphaned_element"
                ))
            }
        }

        return SpecValidationIssues(valid: !issues.contains { $0.severity == .error }, issues: issues)
    }

    /// Moves misplaced fields out of props and, when `lossy` is true, prunes
    /// references to missing elements, like upstream `autoFixSpec`.
    ///
    /// `visible`, `on`, `repeat` and `watch` found inside `props` move to the
    /// element (lossless). Lossy fixes remove child and slot references to
    /// elements that do not exist, except that a repeat container keeps its
    /// references when all of them are missing.
    public static func autoFix(_ spec: Spec, lossy: Bool = true) throws -> (spec: Spec, fixes: [String], fixDetails: [SpecFix]) {
        var details: [SpecFix] = []
        var fixed = JSONObject()
        let elements = try JavaScript.member("elements", of: .object(spec.object))

        for (key, value) in try JavaScript.entries(elements) {
            var element = value
            for field in ["visible", "on", "repeat", "watch"] {
                let props = try JavaScript.member("props", of: element)
                guard props.isTruthy, try JavaScript.hasProperty(field, in: props), !props[field].isUndefined,
                      case var .object(rest) = props, case var .object(updated) = element
                else { continue }
                let moved = rest.removeValue(forKey: field) ?? .undefined
                updated = JSONObject(copying: updated)
                updated["props"] = .object(rest)
                updated[field] = moved
                element = .object(updated)
                details.append(SpecFix(message: "Moved \"\(field)\" from props to element level on \"\(key)\".", lossy: false))
            }
            fixed[key] = element
        }

        if lossy {
            for (key, element) in fixed {
                let children = element["children"]
                guard children.isTruthy, try JavaScript.length(of: children) != 0 else { continue }
                guard case let .array(childKeys) = children else {
                    throw JavaScriptError.typeError("element.children.filter is not a function")
                }
                let present = childKeys.filter { fixed.hasKey($0.javaScriptString) }
                if present.count == childKeys.count { continue }
                if !element["repeat"].isUndefined, present.isEmpty { continue }
                for child in childKeys where !fixed.hasKey(child.javaScriptString) {
                    details.append(SpecFix(
                        message: "Removed reference to undefined element \"\(child.javaScriptString)\" from children of \"\(key)\".",
                        lossy: true
                    ))
                }
                var updated = JSONObject(copying: element.objectValue ?? [:])
                updated["children"] = .array(JSONArray(present))
                fixed[key] = .object(updated)
            }
            for (key, element) in fixed {
                let slots = element["slots"]
                guard slots.isTruthy else { continue }
                var changed = false
                var prunedSlots = JSONObject()
                for (slotName, slotChildren) in try JavaScript.entries(slots) {
                    guard case let .array(childKeys) = slotChildren else {
                        throw JavaScriptError.typeError("childKeys.filter is not a function")
                    }
                    let present = childKeys.filter { fixed.hasKey($0.javaScriptString) }
                    if present.count != childKeys.count {
                        changed = true
                        for child in childKeys where !fixed.hasKey(child.javaScriptString) {
                            details.append(SpecFix(
                                message: "Removed reference to undefined element \"\(child.javaScriptString)\" from slot \"\(slotName)\" of \"\(key)\".",
                                lossy: true
                            ))
                        }
                    }
                    prunedSlots[slotName] = .array(JSONArray(present))
                }
                if changed {
                    var updated = JSONObject(copying: element.objectValue ?? [:])
                    updated["slots"] = .object(prunedSlots)
                    fixed[key] = .object(updated)
                }
            }
        }

        let result = Spec(["root": spec.root, "elements": .object(fixed), "state": spec.state])
        return (result, details.map(\.message), details)
    }

    /// Formats the errors as a repair prompt, like upstream `formatSpecIssues`.
    /// Returns "" when there are no errors.
    public static func formatIssues(_ issues: [SpecIssue]) -> String {
        let errors = issues.filter { $0.severity == .error }
        if errors.isEmpty { return "" }
        return (["The generated UI spec has the following errors:"] + errors.map { "- \($0.message)" }).joined(separator: "\n")
    }
}
