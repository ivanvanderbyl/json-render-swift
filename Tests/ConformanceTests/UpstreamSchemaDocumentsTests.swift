import Testing
@testable import JSONRender

/// The package embeds JSON Schema exports of upstream zod schemas; they must
/// stay identical to what upstream exports.
@Suite("Conformance: embedded upstream schemas")
struct UpstreamSchemaDocumentsTests {
    @Test(arguments: Golden.cases("upstream-schemas"))
    func matchesUpstreamExport(_ golden: GoldenCase) throws {
        let embedded: String = switch golden.name {
        case "ActionConfirmSchema": UpstreamSchemaDocuments.actionConfirm
        case "ActionOnSuccessSchema": UpstreamSchemaDocuments.actionOnSuccess
        case "ActionOnErrorSchema": UpstreamSchemaDocuments.actionOnError
        case "ActionBindingSchema": UpstreamSchemaDocuments.actionBinding
        case "DynamicValueSchema": UpstreamSchemaDocuments.dynamicValue
        case "ValidationCheckSchema": UpstreamSchemaDocuments.validationCheck
        case "ValidationConfigSchema": UpstreamSchemaDocuments.validationConfig
        case "VisibilityConditionSchema": UpstreamSchemaDocuments.visibilityCondition
        case "VisibilityConditionStrictSchema": UpstreamSchemaDocuments.visibilityConditionStrict
        default: ""
        }
        #expect(try JSONValue(parsing: embedded) == golden.output)
    }
}
