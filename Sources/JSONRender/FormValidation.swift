import Observation

/// The validation state of one field, like upstream `FieldValidationState`.
public struct FieldValidationState: Sendable, Equatable {
    public var touched: Bool
    public var validated: Bool
    public var result: ValidationResult?

    public init(touched: Bool = false, validated: Bool = false, result: ValidationResult? = nil) {
        self.touched = touched
        self.validated = validated
        self.result = result
    }

    /// The failed checks' messages, like upstream `useFieldValidation().errors`.
    public var errors: [JSONValue] { result?.errors ?? [] }
    /// True until a validation fails, like upstream `useFieldValidation().isValid`.
    public var isValid: Bool { result?.valid ?? true }
}

/// Registered form fields and their validation results, like upstream
/// `ValidationProvider`.
///
/// Components with checks call ``registerField(_:config:)`` with their bound
/// state path once mounted, and ``validate(_:config:)`` when they choose to
/// (on change, blur or submit). The built-in `validateForm` action calls
/// ``validateAll()``.
@MainActor
@Observable
public final class FormValidation {
    /// Field states by state path, in the order they were first recorded.
    public private(set) var fieldStates: [(path: String, state: FieldValidationState)] = []
    private var configs: [(path: String, config: JSONValue)] = []
    @ObservationIgnored var customFunctions: [String: ValidationFunction]
    @ObservationIgnored var currentState: @MainActor () -> JSONObject = { [:] }
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    init(customFunctions: [String: ValidationFunction]) {
        self.customFunctions = customFunctions
    }

    /// Registers a field's validation config, like upstream `registerField`.
    public func registerField(_ path: String, config: JSONValue) {
        if let index = configs.firstIndex(where: { JavaScript.same($0.path, path) }) {
            configs[index].config = config
        } else {
            configs.append((path, config))
        }
    }

    /// Validates the value at `path` now, like upstream `validate`. Reads the
    /// store directly, so it sees a value written in the same step.
    @discardableResult
    public func validate(_ path: String, config: JSONValue) throws -> ValidationResult {
        let snapshot = currentState()
        // Upstream walks plain "/" segments here, without JSON Pointer escapes.
        var value = JSONValue.object(snapshot)
        for segment in path.split(separator: "/").map(String.init) {
            switch value {
            case let .object(object): value = object[segment] ?? .undefined
            case let .array(array):
                if let index = arrayIndex(segment), Int(index) < array.count { value = array[Int(index)] } else { value = .undefined }
            default: value = .undefined
            }
        }
        let result = try Validation.run(config, context: ValidationContext(value: value, state: .object(snapshot), customFunctions: customFunctions))
        let previous = state(at: path)
        setState(FieldValidationState(touched: previous?.touched ?? true, validated: true, result: result), for: path)
        return result
    }

    /// Marks a field touched, like upstream `touch`.
    public func touch(_ path: String) {
        let previous = state(at: path)
        setState(FieldValidationState(touched: true, validated: previous?.validated ?? false, result: previous?.result), for: path)
    }

    /// Forgets a field's validation state, like upstream `clear`.
    public func clear(_ path: String) {
        fieldStates.removeAll { JavaScript.same($0.path, path) }
        onChange?()
    }

    /// Validates every registered field, like upstream `validateAll`.
    public func validateAll() throws -> Bool {
        var allValid = true
        for (path, config) in configs where try !validate(path, config: config).valid {
            allValid = false
        }
        return allValid
    }

    /// A field's state, like upstream `useFieldValidation().state`.
    public func state(for path: String) -> FieldValidationState {
        state(at: path) ?? FieldValidationState()
    }

    private func state(at path: String) -> FieldValidationState? {
        fieldStates.first { JavaScript.same($0.path, path) }?.state
    }

    private func setState(_ state: FieldValidationState, for path: String) {
        if let index = fieldStates.firstIndex(where: { JavaScript.same($0.path, path) }) {
            fieldStates[index].state = state
        } else {
            fieldStates.append((path, state))
        }
        onChange?()
    }
}
