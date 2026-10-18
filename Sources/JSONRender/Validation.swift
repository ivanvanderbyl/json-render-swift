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
    ///
    /// String lengths count UTF-16 code units, `pattern` uses ECMAScript
    /// regular expression rules and `url` follows the WHATWG URL parser, as
    /// upstream does in JavaScript.
    public static let builtInFunctions: [String: ValidationFunction] = [
        "required": { value, _ in isPresent(value) },
        "email": { value, _ in
            guard case let .string(string) = value else { return false }
            return isEmail(string)
        },
        "minLength": { value, args in
            guard case let .string(string) = value, case let .number(min)? = args["min"] else { return false }
            return Double(JavaScript.length(string)) >= min
        },
        "maxLength": { value, args in
            guard case let .string(string) = value, case let .number(max)? = args["max"] else { return false }
            return Double(JavaScript.length(string)) <= max
        },
        "pattern": { value, args in
            guard case let .string(string) = value, case let .string(pattern)? = args["pattern"],
                  let regex = JavaScriptRegex(pattern)
            else { return false }
            return regex.test(string)
        },
        "min": { value, args in
            guard case let .number(number) = value, case let .number(min)? = args["min"] else { return false }
            return number >= min
        },
        "max": { value, args in
            guard case let .number(number) = value, case let .number(max)? = args["max"] else { return false }
            return number <= max
        },
        "numeric": { value, _ in
            switch value {
            case let .number(number): return !number.isNaN
            case let .string(string): return !JavaScript.trim(string).isEmpty && !JavaScript.stringToNumber(string).isNaN
            default: return false
            }
        },
        "url": { value, _ in
            guard case let .string(string) = value else { return false }
            return WHATWGURL.canParse(string)
        },
        "matches": { value, args in value.strictEquals(args["other"] ?? .undefined) },
        "equalTo": { value, args in value.strictEquals(args["other"] ?? .undefined) },
        "lessThan": { value, args in compare(value, args["other"] ?? .undefined, <, JavaScript.lessThan) },
        "greaterThan": { value, args in compare(value, args["other"] ?? .undefined, >, { JavaScript.lessThan($1, $0) }) },
        "requiredIf": { value, args in
            guard (args["field"] ?? .undefined).isTruthy else { return true }
            return isPresent(value)
        },
    ]

    /// `required`: not null or undefined, not a blank string, not an empty array.
    private static func isPresent(_ value: JSONValue) -> Bool {
        switch value {
        case .undefined, .null: false
        case let .string(string): !JavaScript.trim(string).isEmpty
        case let .array(array): !array.isEmpty
        default: true
        }
    }

    /// `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`: one "@", no whitespace, and a "." in
    /// the domain with at least one character on each side.
    private static func isEmail(_ string: String) -> Bool {
        let units = Array(string.unicodeScalars)
        if units.contains(where: JavaScript.isWhitespace) { return false }
        let parts = units.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = Array(parts[1])
        guard domain.count >= 3 else { return false }
        return domain[1..<(domain.count - 1)].contains(".")
    }

    /// `lessThan` / `greaterThan`: numbers and strings compare directly;
    /// otherwise both sides are coerced with `Number()`.
    private static func compare(
        _ value: JSONValue,
        _ other: JSONValue,
        _ numbers: (Double, Double) -> Bool,
        _ strings: (String, String) -> Bool
    ) -> Bool {
        if value.isNullish || other.isNullish || value == "" || other == "" { return false }
        switch (value, other) {
        case let (.number(a), .number(b)): return numbers(a, b)
        case let (.string(a), .string(b)): return strings(a, b)
        default:
            let a = value.javaScriptNumber
            let b = other.javaScriptNumber
            return !a.isNaN && !b.isNaN && numbers(a, b)
        }
    }

    /// Runs one check, like upstream `runValidationCheck`. Args resolve as
    /// prop expressions against the state. An unknown function passes with a
    /// warning.
    public static func runCheck(_ check: JSONValue, context: ValidationContext) throws -> ValidationCheckResult {
        let type = try JavaScript.member("type", of: check)
        let message = try JavaScript.member("message", of: check)
        var arguments = JSONObject()
        let args = try JavaScript.member("args", of: check)
        if args.isTruthy {
            let argumentContext = ResolutionContext(state: context.state)
            for (key, argument) in try JavaScript.entries(args) {
                arguments[key] = try PropExpression.resolve(argument, in: argumentContext)
            }
        }
        let name = type.javaScriptString
        guard let function = builtInFunctions[name] ?? context.customFunctions[name] else {
            Diagnostics.warn("Unknown validation function: \(name)")
            return ValidationCheckResult(type: type, valid: true, message: message)
        }
        return ValidationCheckResult(type: type, valid: function(context.value, arguments), message: message)
    }

    /// Runs every check of a config, like upstream `runValidation`. When
    /// `enabled` is present and false, the field is valid and no check runs.
    public static func run(_ config: JSONValue, context: ValidationContext) throws -> ValidationResult {
        let enabled = try JavaScript.member("enabled", of: config)
        if enabled.isTruthy, try !Visibility.evaluate(enabled, in: ResolutionContext(state: context.state)) {
            return ValidationResult(valid: true, errors: [], checks: [])
        }
        var checks: [ValidationCheckResult] = []
        var errors: [JSONValue] = []
        let configured = try JavaScript.member("checks", of: config)
        if configured.isTruthy {
            for check in try JavaScript.iterate(configured, expression: "config.checks") {
                let result = try runCheck(check, context: context)
                checks.append(result)
                if !result.valid { errors.append(result.message) }
            }
        }
        return ValidationResult(valid: errors.isEmpty, errors: errors, checks: checks)
    }
}

/// Builders for common checks, like upstream `check`.
public enum Check {
    public static func required(_ message: String = "This field is required") -> JSONObject {
        ["type": "required", "message": .string(message)]
    }

    public static func email(_ message: String = "Invalid email address") -> JSONObject {
        ["type": "email", "message": .string(message)]
    }

    public static func minLength(_ min: Double, _ message: String? = nil) -> JSONObject {
        ["type": "minLength", "args": ["min": .number(min)],
         "message": .string(message ?? "Must be at least \(JavaScript.numberToString(min)) characters")]
    }

    public static func maxLength(_ max: Double, _ message: String? = nil) -> JSONObject {
        ["type": "maxLength", "args": ["max": .number(max)],
         "message": .string(message ?? "Must be at most \(JavaScript.numberToString(max)) characters")]
    }

    public static func pattern(_ pattern: String, _ message: String = "Invalid format") -> JSONObject {
        ["type": "pattern", "args": ["pattern": .string(pattern)], "message": .string(message)]
    }

    public static func min(_ min: Double, _ message: String? = nil) -> JSONObject {
        ["type": "min", "args": ["min": .number(min)],
         "message": .string(message ?? "Must be at least \(JavaScript.numberToString(min))")]
    }

    public static func max(_ max: Double, _ message: String? = nil) -> JSONObject {
        ["type": "max", "args": ["max": .number(max)],
         "message": .string(message ?? "Must be at most \(JavaScript.numberToString(max))")]
    }

    public static func url(_ message: String = "Invalid URL") -> JSONObject {
        ["type": "url", "message": .string(message)]
    }

    public static func numeric(_ message: String = "Must be a number") -> JSONObject {
        ["type": "numeric", "message": .string(message)]
    }

    public static func matches(_ otherPath: String, _ message: String = "Fields must match") -> JSONObject {
        ["type": "matches", "args": ["other": ["$state": .string(otherPath)]], "message": .string(message)]
    }

    public static func equalTo(_ otherPath: String, _ message: String = "Fields must match") -> JSONObject {
        ["type": "equalTo", "args": ["other": ["$state": .string(otherPath)]], "message": .string(message)]
    }

    public static func lessThan(_ otherPath: String, _ message: String? = nil) -> JSONObject {
        ["type": "lessThan", "args": ["other": ["$state": .string(otherPath)]],
         "message": .string(message ?? "Must be less than the compared field")]
    }

    public static func greaterThan(_ otherPath: String, _ message: String? = nil) -> JSONObject {
        ["type": "greaterThan", "args": ["other": ["$state": .string(otherPath)]],
         "message": .string(message ?? "Must be greater than the compared field")]
    }

    public static func requiredIf(_ fieldPath: String, _ message: String = "This field is required") -> JSONObject {
        ["type": "requiredIf", "args": ["field": ["$state": .string(fieldPath)]], "message": .string(message)]
    }
}
