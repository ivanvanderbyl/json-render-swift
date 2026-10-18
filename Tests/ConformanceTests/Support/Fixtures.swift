@testable import JSONRender

/// Swift equivalents of the named functions and directives in
/// Conformance/src/fixtures.mjs, so corpus cases can refer to them by name.
enum Fixtures {
    static let computedFunctions: [String: ComputedFunction] = [
        "fullName": { args in
            .string((args["first"] ?? .undefined).javaScriptString + " " + (args["last"] ?? .undefined).javaScriptString)
        },
        "double": { args in .number((args["value"] ?? .undefined).javaScriptNumber * 2) },
        "echo": { args in .object(args) },
        "argCount": { args in .number(Double(args.count)) },
        "fails": { _ in throw JavaScriptError.error("computed failed") },
    ]

    static let directives: DirectiveRegistry = {
        // The names are valid, so these initialisers cannot throw.
        try! DirectiveRegistry([
            DirectiveDefinition(name: "$double") { value, context in
                .number(try PropExpression.resolve(value["$double"], in: context).javaScriptNumber * 2)
            },
            DirectiveDefinition(name: "$upper") { value, context in
                .string(try PropExpression.resolve(value["$upper"], in: context).javaScriptString.uppercased())
            },
            DirectiveDefinition(name: "$join") { value, context in
                let parts = try (value["$join"].arrayValue ?? []).map { try PropExpression.resolve($0, in: context) }
                let separator = value["separator"].isNullish ? "," : value["separator"].javaScriptString
                return .string(parts.map { $0.isNullish ? "" : $0.javaScriptString }.joined(separator: separator))
            },
            DirectiveDefinition(name: "$fails") { _, _ in throw JavaScriptError.error("directive failed") },
        ])
    }()

    static let validationFunctions: [String: ValidationFunction] = [
        "startsWithA": { value, _ in
            guard case let .string(string) = value else { return false }
            return JavaScript.startsWith(string, "A")
        },
        "isEven": { value, _ in
            guard case let .number(number) = value else { return false }
            return number.truncatingRemainder(dividingBy: 2) == 0
        },
        "hasArg": { _, args in !args.isEmpty },
    ]
}
