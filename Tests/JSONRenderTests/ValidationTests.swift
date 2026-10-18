import Testing
@testable import JSONRender

// Ports upstream tests from packages/core/src/validation.test.ts (json-render 0.21.1).
// Suite and test names match the upstream describe and it names.

/// Calls a built-in validation function by name, like
/// `builtInValidationFunctions[name](value, args)` upstream. Fails the test
/// when the function is missing.
private func builtIn(_ name: String, _ value: JSONValue, _ args: JSONObject = [:]) throws -> Bool {
    let function = try #require(Validation.builtInFunctions[name])
    return function(value, args)
}

// MARK: - builtInValidationFunctions

@Suite("validation.test.ts › builtInValidationFunctions › required")
struct ValidationBuiltInRequiredTests {
    @Test("passes for non-empty values")
    func passesForNonEmpty() throws {
        #expect(try builtIn("required", "hello") == true)
        #expect(try builtIn("required", 0) == true)
        #expect(try builtIn("required", false) == true)
        #expect(try builtIn("required", ["item"]) == true)
        #expect(try builtIn("required", ["key": "value"]) == true)
    }

    @Test("fails for empty values")
    func failsForEmpty() throws {
        #expect(try builtIn("required", "") == false)
        #expect(try builtIn("required", "   ") == false)
        #expect(try builtIn("required", nil) == false)
        #expect(try builtIn("required", .undefined) == false)
        #expect(try builtIn("required", []) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › email")
struct ValidationBuiltInEmailTests {
    @Test("passes for valid emails")
    func passesForValid() throws {
        #expect(try builtIn("email", "test@example.com") == true)
        #expect(try builtIn("email", "user.name@domain.co") == true)
        #expect(try builtIn("email", "a@b.c") == true)
    }

    @Test("fails for invalid emails")
    func failsForInvalid() throws {
        #expect(try builtIn("email", "invalid") == false)
        #expect(try builtIn("email", "missing@domain") == false)
        #expect(try builtIn("email", "@domain.com") == false)
        #expect(try builtIn("email", "user@") == false)
        #expect(try builtIn("email", 123) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › minLength")
struct ValidationBuiltInMinLengthTests {
    @Test("passes when string meets minimum length")
    func passesAtMinimum() throws {
        #expect(try builtIn("minLength", "hello", ["min": 3]) == true)
        #expect(try builtIn("minLength", "abc", ["min": 3]) == true)
        #expect(try builtIn("minLength", "abcdef", ["min": 3]) == true)
    }

    @Test("fails when string is too short")
    func failsWhenTooShort() throws {
        #expect(try builtIn("minLength", "hi", ["min": 3]) == false)
        #expect(try builtIn("minLength", "", ["min": 1]) == false)
    }

    @Test("fails for non-strings")
    func failsForNonStrings() throws {
        #expect(try builtIn("minLength", 123, ["min": 1]) == false)
    }

    @Test("fails when min is not provided")
    func failsWithoutMin() throws {
        #expect(try builtIn("minLength", "hello", [:]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › maxLength")
struct ValidationBuiltInMaxLengthTests {
    @Test("passes when string meets maximum length")
    func passesAtMaximum() throws {
        #expect(try builtIn("maxLength", "hi", ["max": 5]) == true)
        #expect(try builtIn("maxLength", "hello", ["max": 5]) == true)
    }

    @Test("fails when string exceeds maximum")
    func failsWhenTooLong() throws {
        #expect(try builtIn("maxLength", "hello!", ["max": 5]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › pattern")
struct ValidationBuiltInPatternTests {
    @Test("passes when string matches pattern")
    func passesWhenMatching() throws {
        #expect(try builtIn("pattern", "abc123", ["pattern": "^[a-z0-9]+$"]) == true)
    }

    @Test("fails when string does not match pattern")
    func failsWhenNotMatching() throws {
        #expect(try builtIn("pattern", "ABC", ["pattern": "^[a-z]+$"]) == false)
    }

    @Test("fails for invalid regex pattern")
    func failsForInvalidPattern() throws {
        #expect(try builtIn("pattern", "test", ["pattern": "[invalid"]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › min")
struct ValidationBuiltInMinTests {
    @Test("passes when number meets minimum")
    func passesAtMinimum() throws {
        #expect(try builtIn("min", 5, ["min": 3]) == true)
        #expect(try builtIn("min", 3, ["min": 3]) == true)
    }

    @Test("fails when number is below minimum")
    func failsBelowMinimum() throws {
        #expect(try builtIn("min", 2, ["min": 3]) == false)
    }

    @Test("fails for non-numbers")
    func failsForNonNumbers() throws {
        #expect(try builtIn("min", "5", ["min": 3]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › max")
struct ValidationBuiltInMaxTests {
    @Test("passes when number meets maximum")
    func passesAtMaximum() throws {
        #expect(try builtIn("max", 3, ["max": 5]) == true)
        #expect(try builtIn("max", 5, ["max": 5]) == true)
    }

    @Test("fails when number exceeds maximum")
    func failsAboveMaximum() throws {
        #expect(try builtIn("max", 6, ["max": 5]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › numeric")
struct ValidationBuiltInNumericTests {
    @Test("passes for numbers")
    func passesForNumbers() throws {
        #expect(try builtIn("numeric", 42) == true)
        #expect(try builtIn("numeric", 3.14) == true)
        #expect(try builtIn("numeric", 0) == true)
    }

    @Test("passes for numeric strings")
    func passesForNumericStrings() throws {
        #expect(try builtIn("numeric", "42") == true)
        #expect(try builtIn("numeric", "3.14") == true)
    }

    @Test("fails for non-numeric values")
    func failsForNonNumeric() throws {
        #expect(try builtIn("numeric", "abc") == false)
        #expect(try builtIn("numeric", .number(.nan)) == false)
        #expect(try builtIn("numeric", nil) == false)
    }

    @Test("fails for strings with trailing non-numeric characters")
    func failsForTrailingCharacters() throws {
        #expect(try builtIn("numeric", "123abc") == false)
        #expect(try builtIn("numeric", "99bottles") == false)
    }

    @Test("fails for empty and whitespace-only strings")
    func failsForEmptyAndWhitespace() throws {
        #expect(try builtIn("numeric", "") == false)
        #expect(try builtIn("numeric", "   ") == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › url")
struct ValidationBuiltInURLTests {
    @Test("passes for valid URLs")
    func passesForValid() throws {
        #expect(try builtIn("url", "https://example.com") == true)
        #expect(try builtIn("url", "http://localhost:3000") == true)
        #expect(try builtIn("url", "https://example.com/path?query=1") == true)
    }

    @Test("fails for invalid URLs")
    func failsForInvalid() throws {
        #expect(try builtIn("url", "not-a-url") == false)
        #expect(try builtIn("url", "example.com") == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › matches")
struct ValidationBuiltInMatchesTests {
    @Test("passes when values match")
    func passesWhenMatching() throws {
        #expect(try builtIn("matches", "password", ["other": "password"]) == true)
        #expect(try builtIn("matches", 123, ["other": 123]) == true)
    }

    @Test("fails when values do not match")
    func failsWhenDifferent() throws {
        #expect(try builtIn("matches", "password", ["other": "different"]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › equalTo")
struct ValidationBuiltInEqualToTests {
    @Test("passes when values are equal")
    func passesWhenEqual() throws {
        #expect(try builtIn("equalTo", "abc", ["other": "abc"]) == true)
    }

    @Test("fails when values differ")
    func failsWhenDifferent() throws {
        #expect(try builtIn("equalTo", "abc", ["other": "xyz"]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › lessThan")
struct ValidationBuiltInLessThanTests {
    @Test("passes when value is less than other")
    func passesWhenLess() throws {
        #expect(try builtIn("lessThan", 3, ["other": 5]) == true)
    }

    @Test("fails when value equals other")
    func failsWhenEqual() throws {
        #expect(try builtIn("lessThan", 5, ["other": 5]) == false)
    }

    @Test("fails when value is greater than other")
    func failsWhenGreater() throws {
        #expect(try builtIn("lessThan", 7, ["other": 5]) == false)
    }

    @Test("coerces numeric string vs number")
    func coercesNumericString() throws {
        #expect(try builtIn("lessThan", "3", ["other": 5]) == true)
    }

    @Test("fails coercion when non-numeric string")
    func failsCoercionForNonNumericString() throws {
        #expect(try builtIn("lessThan", "abc", ["other": 5]) == false)
    }

    @Test("passes for string comparison (ISO dates)")
    func passesForISODates() throws {
        #expect(try builtIn("lessThan", "2026-01-01", ["other": "2026-06-15"]) == true)
    }

    @Test("fails for equal strings")
    func failsForEqualStrings() throws {
        #expect(try builtIn("lessThan", "2026-01-01", ["other": "2026-01-01"]) == false)
    }

    @Test("returns false when value is empty string")
    func falseForEmptyValue() throws {
        #expect(try builtIn("lessThan", "", ["other": 5]) == false)
    }

    @Test("returns false when other is empty string")
    func falseForEmptyOther() throws {
        #expect(try builtIn("lessThan", 3, ["other": ""]) == false)
    }

    @Test("returns false when value is empty string vs non-empty string")
    func falseForEmptyValueAgainstString() throws {
        #expect(try builtIn("lessThan", "", ["other": "abc"]) == false)
    }

    @Test("returns false when other is empty string vs non-empty string")
    func falseForEmptyOtherAgainstString() throws {
        #expect(try builtIn("lessThan", "abc", ["other": ""]) == false)
    }

    @Test("returns false when other is null")
    func falseForNullOther() throws {
        #expect(try builtIn("lessThan", 3, ["other": nil]) == false)
    }

    @Test("returns false when value is null")
    func falseForNullValue() throws {
        #expect(try builtIn("lessThan", nil, ["other": 5]) == false)
    }

    @Test("returns false when other is undefined")
    func falseForUndefinedOther() throws {
        #expect(try builtIn("lessThan", 3, ["other": .undefined]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › greaterThan")
struct ValidationBuiltInGreaterThanTests {
    @Test("passes when value is greater than other")
    func passesWhenGreater() throws {
        #expect(try builtIn("greaterThan", 7, ["other": 5]) == true)
    }

    @Test("fails when value equals other")
    func failsWhenEqual() throws {
        #expect(try builtIn("greaterThan", 5, ["other": 5]) == false)
    }

    @Test("fails when value is less than other")
    func failsWhenLess() throws {
        #expect(try builtIn("greaterThan", 3, ["other": 5]) == false)
    }

    @Test("coerces numeric string vs number")
    func coercesNumericString() throws {
        #expect(try builtIn("greaterThan", "7", ["other": 5]) == true)
    }

    @Test("fails coercion when non-numeric string")
    func failsCoercionForNonNumericString() throws {
        #expect(try builtIn("greaterThan", "abc", ["other": 5]) == false)
    }

    @Test("passes for string comparison (ISO dates)")
    func passesForISODates() throws {
        #expect(try builtIn("greaterThan", "2026-06-15", ["other": "2026-01-01"]) == true)
    }

    @Test("fails for lesser strings")
    func failsForLesserStrings() throws {
        #expect(try builtIn("greaterThan", "2026-01-01", ["other": "2026-06-15"]) == false)
    }

    @Test("returns false when value is empty string")
    func falseForEmptyValue() throws {
        #expect(try builtIn("greaterThan", "", ["other": 5]) == false)
    }

    @Test("returns false when other is empty string")
    func falseForEmptyOther() throws {
        #expect(try builtIn("greaterThan", 3, ["other": ""]) == false)
    }

    @Test("returns false when value is empty string vs non-empty string")
    func falseForEmptyValueAgainstString() throws {
        #expect(try builtIn("greaterThan", "", ["other": "abc"]) == false)
    }

    @Test("returns false when other is empty string vs non-empty string")
    func falseForEmptyOtherAgainstString() throws {
        #expect(try builtIn("greaterThan", "abc", ["other": ""]) == false)
    }

    @Test("returns false when other is null")
    func falseForNullOther() throws {
        #expect(try builtIn("greaterThan", 3, ["other": nil]) == false)
    }

    @Test("returns false when value is undefined")
    func falseForUndefinedValue() throws {
        #expect(try builtIn("greaterThan", .undefined, ["other": 5]) == false)
    }

    @Test("returns false when value is null")
    func falseForNullValue() throws {
        #expect(try builtIn("greaterThan", nil, ["other": 5]) == false)
    }
}

@Suite("validation.test.ts › builtInValidationFunctions › requiredIf")
struct ValidationBuiltInRequiredIfTests {
    @Test("passes when condition is falsy (field not required)")
    func passesWhenConditionFalsy() throws {
        #expect(try builtIn("requiredIf", "", ["field": false]) == true)
        #expect(try builtIn("requiredIf", "", ["field": ""]) == true)
        #expect(try builtIn("requiredIf", "", ["field": nil]) == true)
        #expect(try builtIn("requiredIf", "", ["field": .undefined]) == true)
    }

    @Test("fails when condition is truthy and value is empty")
    func failsWhenConditionTruthyAndEmpty() throws {
        #expect(try builtIn("requiredIf", "", ["field": true]) == false)
        #expect(try builtIn("requiredIf", nil, ["field": "yes"]) == false)
        #expect(try builtIn("requiredIf", .undefined, ["field": 1]) == false)
    }

    @Test("passes when condition is truthy and value is present")
    func passesWhenConditionTruthyAndPresent() throws {
        #expect(try builtIn("requiredIf", "hello", ["field": true]) == true)
        #expect(try builtIn("requiredIf", 42, ["field": true]) == true)
    }
}

// MARK: - runValidationCheck

@Suite("validation.test.ts › runValidationCheck")
struct ValidationRunCheckTests {
    @Test("runs a validation check and returns result")
    func runsCheck() throws {
        let result = try Validation.runCheck(
            ["type": "required", "message": "Required"],
            context: ValidationContext(value: "hello", state: [:])
        )

        #expect(result.type == "required")
        #expect(result.valid == true)
        #expect(result.message == "Required")
    }

    @Test("resolves dynamic args from stateModel")
    func resolvesDynamicArgs() throws {
        let result = try Validation.runCheck(
            [
                "type": "minLength",
                "args": ["min": ["$state": "/minLen"]],
                "message": "Too short",
            ],
            context: ValidationContext(value: "hi", state: ["minLen": 5])
        )

        #expect(result.valid == false)
    }

    @Test("returns valid for unknown functions with warning")
    func unknownFunctionIsValid() throws {
        let result = try Validation.runCheck(
            ["type": "unknownFunction", "message": "Unknown"],
            context: ValidationContext(value: "test", state: [:])
        )

        #expect(result.valid == true)
    }

    @Test("uses custom validation functions")
    func usesCustomFunctions() throws {
        let customFunctions: [String: ValidationFunction] = [
            "startsWithA": { value, _ in value.stringValue?.hasPrefix("A") ?? false },
        ]

        let result = try Validation.runCheck(
            ["type": "startsWithA", "message": "Must start with A"],
            context: ValidationContext(value: "Apple", state: [:], customFunctions: customFunctions)
        )

        #expect(result.valid == true)
    }
}

// MARK: - runValidation

@Suite("validation.test.ts › runValidation")
struct ValidationRunTests {
    @Test("runs all validation checks")
    func runsAllChecks() throws {
        let result = try Validation.run(
            [
                "checks": [
                    ["type": "required", "message": "Required"],
                    ["type": "email", "message": "Invalid email"],
                ],
            ],
            context: ValidationContext(value: "test@example.com", state: [:])
        )

        #expect(result.valid == true)
        #expect(result.errors.count == 0)
        #expect(result.checks.count == 2)
    }

    @Test("collects all errors")
    func collectsAllErrors() throws {
        let result = try Validation.run(
            [
                "checks": [
                    ["type": "required", "message": "Required"],
                    ["type": "email", "message": "Invalid email"],
                ],
            ],
            context: ValidationContext(value: "", state: [:])
        )

        #expect(result.valid == false)
        #expect(result.errors.contains("Required"))
        #expect(result.errors.contains("Invalid email"))
    }

    @Test("skips validation when enabled condition is false")
    func skipsWhenDisabled() throws {
        let result = try Validation.run(
            [
                "checks": [["type": "required", "message": "Required"]],
                // False because /enabled is not set.
                "enabled": ["$state": "/enabled", "eq": true],
            ],
            context: ValidationContext(value: "", state: [:])
        )

        #expect(result.valid == true)
        #expect(result.checks.count == 0)
    }

    @Test("runs validation when enabled condition is true")
    func runsWhenEnabled() throws {
        let result = try Validation.run(
            [
                "checks": [["type": "required", "message": "Required"]],
                // True because /enabled is truthy.
                "enabled": ["$state": "/enabled"],
            ],
            context: ValidationContext(value: "", state: ["enabled": true])
        )

        #expect(result.valid == false)
    }

    @Test("returns valid when no checks defined")
    func validWithoutChecks() throws {
        let result = try Validation.run([:], context: ValidationContext(value: "", state: [:]))

        #expect(result.valid == true)
        #expect(result.checks.count == 0)
    }
}

// MARK: - check helper

@Suite("validation.test.ts › check helper › required")
struct ValidationCheckHelperRequiredTests {
    @Test("creates required check with default message")
    func defaultMessage() {
        let c = Check.required()

        #expect(c["type"] == "required")
        #expect(c["message"] == "This field is required")
    }

    @Test("creates required check with custom message")
    func customMessage() {
        let c = Check.required("Custom message")

        #expect(c["message"] == "Custom message")
    }
}

@Suite("validation.test.ts › check helper › email")
struct ValidationCheckHelperEmailTests {
    @Test("creates email check with default message")
    func defaultMessage() {
        let c = Check.email()

        #expect(c["type"] == "email")
        #expect(c["message"] == "Invalid email address")
    }
}

@Suite("validation.test.ts › check helper › minLength")
struct ValidationCheckHelperMinLengthTests {
    @Test("creates minLength check with args")
    func createsWithArgs() {
        let c = Check.minLength(5, "Too short")

        #expect(c["type"] == "minLength")
        #expect(c["args"] == ["min": 5])
        #expect(c["message"] == "Too short")
    }

    @Test("uses default message")
    func defaultMessage() {
        let c = Check.minLength(3)

        #expect(c["message"] == "Must be at least 3 characters")
    }
}

@Suite("validation.test.ts › check helper › maxLength")
struct ValidationCheckHelperMaxLengthTests {
    @Test("creates maxLength check with args")
    func createsWithArgs() {
        let c = Check.maxLength(100)

        #expect(c["type"] == "maxLength")
        #expect(c["args"] == ["max": 100])
    }
}

@Suite("validation.test.ts › check helper › pattern")
struct ValidationCheckHelperPatternTests {
    @Test("creates pattern check")
    func createsPatternCheck() {
        let c = Check.pattern("^[a-z]+$", "Letters only")

        #expect(c["type"] == "pattern")
        #expect(c["args"] == ["pattern": "^[a-z]+$"])
        #expect(c["message"] == "Letters only")
    }
}

@Suite("validation.test.ts › check helper › min")
struct ValidationCheckHelperMinTests {
    @Test("creates min check")
    func createsMinCheck() {
        let c = Check.min(0, "Must be positive")

        #expect(c["type"] == "min")
        #expect(c["args"] == ["min": 0])
    }
}

@Suite("validation.test.ts › check helper › max")
struct ValidationCheckHelperMaxTests {
    @Test("creates max check")
    func createsMaxCheck() {
        let c = Check.max(100)

        #expect(c["type"] == "max")
        #expect(c["args"] == ["max": 100])
    }
}

@Suite("validation.test.ts › check helper › url")
struct ValidationCheckHelperURLTests {
    @Test("creates url check")
    func createsURLCheck() {
        let c = Check.url("Must be a URL")

        #expect(c["type"] == "url")
        #expect(c["message"] == "Must be a URL")
    }
}

@Suite("validation.test.ts › check helper › numeric")
struct ValidationCheckHelperNumericTests {
    @Test("creates numeric check with default message")
    func defaultMessage() {
        let c = Check.numeric()

        #expect(c["type"] == "numeric")
        #expect(c["message"] == "Must be a number")
    }

    @Test("creates numeric check with custom message")
    func customMessage() {
        let c = Check.numeric("Numbers only")

        #expect(c["type"] == "numeric")
        #expect(c["message"] == "Numbers only")
    }
}

@Suite("validation.test.ts › check helper › matches")
struct ValidationCheckHelperMatchesTests {
    @Test("creates matches check with path reference")
    func createsWithPathReference() {
        let c = Check.matches("/password", "Passwords must match")

        #expect(c["type"] == "matches")
        #expect(c["args"] == ["other": ["$state": "/password"]])
        #expect(c["message"] == "Passwords must match")
    }
}

@Suite("validation.test.ts › check helper › equalTo")
struct ValidationCheckHelperEqualToTests {
    @Test("creates equalTo check with path reference")
    func createsWithPathReference() {
        let c = Check.equalTo("/email", "Emails must match")

        #expect(c["type"] == "equalTo")
        #expect(c["args"] == ["other": ["$state": "/email"]])
        #expect(c["message"] == "Emails must match")
    }
}

@Suite("validation.test.ts › check helper › lessThan")
struct ValidationCheckHelperLessThanTests {
    @Test("creates lessThan check with path reference")
    func createsWithPathReference() {
        let c = Check.lessThan("/maxValue", "Must be less")

        #expect(c["type"] == "lessThan")
        #expect(c["args"] == ["other": ["$state": "/maxValue"]])
        #expect(c["message"] == "Must be less")
    }
}

@Suite("validation.test.ts › check helper › greaterThan")
struct ValidationCheckHelperGreaterThanTests {
    @Test("creates greaterThan check with path reference")
    func createsWithPathReference() {
        let c = Check.greaterThan("/minValue")

        #expect(c["type"] == "greaterThan")
        #expect(c["args"] == ["other": ["$state": "/minValue"]])
    }
}

@Suite("validation.test.ts › check helper › requiredIf")
struct ValidationCheckHelperRequiredIfTests {
    @Test("creates requiredIf check with path reference")
    func createsWithPathReference() {
        let c = Check.requiredIf("/toggle", "Required when toggle is on")

        #expect(c["type"] == "requiredIf")
        #expect(c["args"] == ["field": ["$state": "/toggle"]])
        #expect(c["message"] == "Required when toggle is on")
    }
}

// MARK: - Deep arg resolution in runValidationCheck

@Suite("validation.test.ts › deep arg resolution")
struct ValidationDeepArgResolutionTests {
    @Test("resolves nested $state refs in validation args")
    func resolvesNestedStateRefs() throws {
        let result = try Validation.runCheck(
            [
                "type": "matches",
                "args": ["other": ["$state": "/form/password"]],
                "message": "Passwords must match",
            ],
            context: ValidationContext(value: "secret123", state: ["form": ["password": "secret123"]])
        )
        #expect(result.valid == true)
    }

    @Test("resolves $state in cross-field lessThan check")
    func resolvesStateInLessThan() throws {
        let result = try Validation.runCheck(
            [
                "type": "lessThan",
                "args": ["other": ["$state": "/form/maxPrice"]],
                "message": "Must be less than max price",
            ],
            context: ValidationContext(value: 50, state: ["form": ["maxPrice": 100]])
        )
        #expect(result.valid == true)
    }

    @Test("resolves $state in requiredIf check")
    func resolvesStateInRequiredIf() throws {
        let result = try Validation.runCheck(
            [
                "type": "requiredIf",
                "args": ["field": ["$state": "/form/enableEmail"]],
                "message": "Email is required",
            ],
            context: ValidationContext(value: "", state: ["form": ["enableEmail": true]])
        )
        #expect(result.valid == false)
    }

    @Test("passes requiredIf when condition is false")
    func passesRequiredIfWhenConditionFalse() throws {
        let result = try Validation.runCheck(
            [
                "type": "requiredIf",
                "args": ["field": ["$state": "/form/enableEmail"]],
                "message": "Email is required",
            ],
            context: ValidationContext(value: "", state: ["form": ["enableEmail": false]])
        )
        #expect(result.valid == true)
    }
}
