/// A form validation function: receives the field value and the check's
/// resolved `args`, like upstream `ValidationFunction`.
public typealias ValidationFunction = @Sendable (JSONValue, JSONObject) -> Bool

/// What a validation check needs, like upstream `ValidationContext`.
public struct ValidationContext: Sendable {
    /// The field value being validated.
    public var value: JSONValue
    /// The state model, for resolving `$state` args.
    public var state: JSONValue
    /// Custom functions, consulted after the built-in ones.
    public var customFunctions: [String: ValidationFunction]

    public init(value: JSONValue, state: JSONValue = [:], customFunctions: [String: ValidationFunction] = [:]) {
        self.value = value
        self.state = state
        self.customFunctions = customFunctions
    }
}

/// The outcome of one check, like upstream `ValidationCheckResult`.
public struct ValidationCheckResult: Sendable, Equatable {
    public var type: JSONValue
    public var valid: Bool
    public var message: JSONValue

    public init(type: JSONValue, valid: Bool, message: JSONValue) {
        self.type = type
        self.valid = valid
        self.message = message
    }
}

/// The outcome of all checks for a field, like upstream `ValidationResult`.
public struct ValidationResult: Sendable, Equatable {
    public var valid: Bool
    /// The messages of the checks that failed, in check order.
    public var errors: [JSONValue]
    public var checks: [ValidationCheckResult]

    public init(valid: Bool, errors: [JSONValue], checks: [ValidationCheckResult]) {
        self.valid = valid
        self.errors = errors
        self.checks = checks
    }
}

/// Form field validation, like upstream `validation.ts`.
///
/// A check is an object `{ "type": name, "args": {...}, "message": text }`.
/// A config is `{ "checks": [...], "validateOn": "change" | "blur" | "submit",
/// "enabled": condition }`.
public enum Validation {
    /// The built-in functions, like upstream `builtInValidationFunctions`:
    /// required, email, minLength, maxLength, pattern, min, max, numeric, url,
    /// matches, equalTo, lessThan, greaterThan and requiredIf.
    public static let builtInFunctions: [String: ValidationFunction] = [:]

    /// Runs one check, like upstream `runValidationCheck`. Args resolve as
    /// prop expressions. An unknown function passes with a warning.
    public static func runCheck(_ check: JSONValue, context: ValidationContext) throws -> ValidationCheckResult {
        ValidationCheckResult(type: .undefined, valid: false, message: .undefined)
    }

    /// Runs every check of a config, like upstream `runValidation`. When
    /// `enabled` is present and false, the field is valid and no check runs.
    public static func run(_ config: JSONValue, context: ValidationContext) throws -> ValidationResult {
        ValidationResult(valid: false, errors: [], checks: [])
    }
}

/// Builders for common checks, like upstream `check`.
public enum Check {
    public static func required(_ message: String = "This field is required") -> JSONObject { [:] }
    public static func email(_ message: String = "Invalid email address") -> JSONObject { [:] }
    public static func minLength(_ min: Double, _ message: String? = nil) -> JSONObject { [:] }
    public static func maxLength(_ max: Double, _ message: String? = nil) -> JSONObject { [:] }
    public static func pattern(_ pattern: String, _ message: String = "Invalid format") -> JSONObject { [:] }
    public static func min(_ min: Double, _ message: String? = nil) -> JSONObject { [:] }
    public static func max(_ max: Double, _ message: String? = nil) -> JSONObject { [:] }
    public static func url(_ message: String = "Invalid URL") -> JSONObject { [:] }
    public static func numeric(_ message: String = "Must be a number") -> JSONObject { [:] }
    public static func matches(_ otherPath: String, _ message: String = "Fields must match") -> JSONObject { [:] }
    public static func equalTo(_ otherPath: String, _ message: String = "Fields must match") -> JSONObject { [:] }
    public static func lessThan(_ otherPath: String, _ message: String? = nil) -> JSONObject { [:] }
    public static func greaterThan(_ otherPath: String, _ message: String? = nil) -> JSONObject { [:] }
    public static func requiredIf(_ fieldPath: String, _ message: String = "This field is required") -> JSONObject { [:] }
}
