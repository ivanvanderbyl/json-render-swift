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
    public static func validate(_ spec: Spec, checkOrphans: Bool = false) throws -> SpecValidationIssues {
        SpecValidationIssues(valid: false, issues: [])
    }

    /// Moves misplaced fields out of props and, when `lossy` is true, prunes
    /// references to missing elements, like upstream `autoFixSpec`.
    public static func autoFix(_ spec: Spec, lossy: Bool = true) throws -> (spec: Spec, fixes: [String], fixDetails: [SpecFix]) {
        (spec, [], [])
    }

    /// Formats the errors as a repair prompt, like upstream `formatSpecIssues`.
    public static func formatIssues(_ issues: [SpecIssue]) -> String { "" }
}
