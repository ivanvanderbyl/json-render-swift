/// Upstream's action schemas: `ActionBindingSchema`, `ActionConfirmSchema`,
/// `ActionOnSuccessSchema` and `ActionOnErrorSchema`.
public enum ActionSchemas {
    public static let binding = UpstreamSchemas.compile(UpstreamSchemaDocuments.actionBinding)
    public static let confirm = UpstreamSchemas.compile(UpstreamSchemaDocuments.actionConfirm)
    public static let onSuccess = UpstreamSchemas.compile(UpstreamSchemaDocuments.actionOnSuccess)
    public static let onError = UpstreamSchemas.compile(UpstreamSchemaDocuments.actionOnError)
}

extension DynamicValue {
    /// Upstream `DynamicValueSchema`: a string, number, boolean, null or `{ "$state": string }`.
    public static let schema = UpstreamSchemas.compile(UpstreamSchemaDocuments.dynamicValue)
}

extension Validation {
    /// Upstream `ValidationCheckSchema`.
    public static let checkSchema = UpstreamSchemas.compile(UpstreamSchemaDocuments.validationCheck)
    /// Upstream `ValidationConfigSchema`.
    public static let configSchema = UpstreamSchemas.compile(UpstreamSchemaDocuments.validationConfig)
}

extension Visibility {
    /// Upstream `VisibilityConditionSchema`.
    public static let conditionSchema = UpstreamSchemas.compile(UpstreamSchemaDocuments.visibilityCondition)
    /// Upstream `VisibilityConditionStrictSchema`, used by spec validation.
    public static let strictConditionSchema = UpstreamSchemas.compile(UpstreamSchemaDocuments.visibilityConditionStrict)
}

enum UpstreamSchemas {
    /// Compiles an embedded document. The documents are fixed and tested, so
    /// failure here is a programming error.
    static func compile(_ document: String) -> JSONSchema {
        do {
            return try JSONSchema(JSONValue(parsing: document))
        } catch {
            preconditionFailure("Embedded upstream schema does not compile: \(error)")
        }
    }
}
