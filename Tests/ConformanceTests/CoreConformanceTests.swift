import Testing
@testable import JSONRender

// Checks the Swift core against goldens produced by upstream @json-render/core
// 0.21.1 (see Conformance/src/suites). Each corpus case is one test argument.

/// Runs `body`, capturing its value or error together with any diagnostics,
/// in the shape the conformance suites record.
private func captureWithMessages(_ body: () throws -> JSONValue) -> JSONValue {
    let recorder = MessageRecorder()
    var result = recorder.record { Tagged.capture(body) }
    result["messages"] = recorder.encoded
    return result
}

private func context(_ raw: JSONValue) -> ResolutionContext {
    let raw = Tagged.decode(raw)
    var context = ResolutionContext(state: raw["state"].isUndefined ? [:] : raw["state"])
    if raw.objectValue?.hasKey("repeatItem") == true { context.repeatItem = raw["repeatItem"] }
    if case let .number(index) = raw["repeatIndex"] { context.repeatIndex = Int(index) }
    if case let .string(base) = raw["repeatBasePath"] { context.repeatBasePath = base }
    if raw["functions"] == true { context.functions = Fixtures.computedFunctions }
    if raw["directives"] == true { context.directives = Fixtures.directives }
    return context
}

@Suite("Conformance: paths")
struct PathsConformanceTests {
    @Test(arguments: Golden.cases("paths"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        try withDivergence(golden) {
            let args = Tagged.decode(golden.input["args"]).arrayValue ?? []
            func arg(_ index: Int) -> JSONValue { args.indices.contains(index) ? args[index] : .undefined }
            func mutate(_ body: (inout JSONValue) throws -> Void) -> JSONValue {
                var target = arg(0)
                do {
                    try body(&target)
                    return ["value": Tagged.encode(target)]
                } catch {
                    return ["threw": .string(String(describing: error)), "partial": Tagged.encode(target)]
                }
            }
            let actual: JSONValue
            switch golden.input["op"].stringValue {
            case "get": actual = Tagged.capture { arg(0).value(atPath: arg(1).stringValue ?? "") }
            case "set": actual = mutate { try $0.write(arg(2), atPath: arg(1).stringValue ?? "", mode: .set) }
            case "add": actual = mutate { try $0.write(arg(2), atPath: arg(1).stringValue ?? "", mode: .add) }
            case "remove": actual = mutate { try $0.remove(atPath: arg(1).stringValue ?? "") }
            case "immutableSet":
                actual = Tagged.capture {
                    let root = arg(0).objectValue ?? [:]
                    let next = StateUpdate.setting(arg(2), atPath: arg(1).stringValue ?? "", in: root)
                    let shared = root.keys.filter { key in
                        next.hasKey(key) && (next[key] ?? .undefined).strictEquals(root[key] ?? .undefined)
                    }
                    return [
                        "result": .object(next),
                        "sameRoot": .bool(next.isIdentical(to: root)),
                        "sharedKeys": .array(JSONArray(shared.map(JSONValue.string))),
                    ]
                }
            case "repeatStatePath":
                actual = Tagged.capture { try RepeatScope.resolveStatePath(arg(0), base: arg(1).stringValue).map(JSONValue.string) ?? .undefined }
            case "repeatItemStatePath":
                actual = Tagged.capture { .string(RepeatScope.itemStatePath(arg(0).stringValue ?? "", index: Int(arg(1).numberValue ?? 0))) }
            case "findFormValue":
                actual = Tagged.capture { FormValue.find(arg(0).stringValue ?? "", params: arg(1).objectValue, state: arg(2).objectValue) }
            case "resolveDynamicValue":
                actual = Tagged.capture { try DynamicValue.resolve(arg(0), state: arg(1)) }
            case "flatten":
                actual = Tagged.capture { .object(JSONPointer.flatten(arg(0).objectValue ?? [:])) }
            default:
                Issue.record("unknown op")
                return
            }
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output), Swift \(actual)")
        }
    }
}

@Suite("Conformance: visibility")
struct VisibilityConformanceTests {
    @Test(arguments: Golden.cases("visibility"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        try withDivergence(golden) {
            let condition = Tagged.decode(golden.input["condition"])
            let raw = Tagged.decode(golden.input["context"])
            var context = ResolutionContext(state: raw["stateModel"].isUndefined ? [:] : raw["stateModel"])
            if raw.objectValue?.hasKey("repeatItem") == true { context.repeatItem = raw["repeatItem"] }
            if case let .number(index) = raw["repeatIndex"] { context.repeatIndex = Int(index) }
            let actual: JSONValue
            switch golden.input["op"].stringValue {
            case "evaluate": actual = Tagged.capture { .bool(try Visibility.evaluate(condition, in: context)) }
            case "usesItemScope": actual = Tagged.capture { .bool(try Visibility.usesItemScope(condition)) }
            case "split":
                actual = Tagged.capture {
                    let split = try Visibility.splitRepeatVisibility(condition)
                    return ["container": split.container, "itemFilter": split.itemFilter]
                }
            case "strictValid": actual = Tagged.capture { .bool(Visibility.isValid(condition)) }
            default:
                Issue.record("unknown op")
                return
            }
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output), Swift \(actual)")
        }
    }
}

@Suite("Conformance: props")
struct PropsConformanceTests {
    @Test(arguments: Golden.cases("props"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        try withDivergence(golden) {
            let value = Tagged.decode(golden.input["value"])
            let context = context(golden.input["context"])
            let actual: JSONValue
            switch golden.input["op"].stringValue {
            case "resolve": actual = captureWithMessages { try PropExpression.resolve(value, in: context) }
            case "resolveProps": actual = captureWithMessages { .object(try PropExpression.resolveProps(value.objectValue ?? [:], in: context)) }
            case "bindings":
                actual = captureWithMessages {
                    guard let bindings = PropExpression.bindings(for: value.objectValue ?? [:], in: context) else { return .undefined }
                    var object = JSONObject()
                    for (key, _) in value.objectValue ?? [:] where bindings[key] != nil { object[key] = .string(bindings[key]!) }
                    return .object(object)
                }
            case "actionParam": actual = captureWithMessages { try PropExpression.resolveActionParam(value, in: context) }
            default:
                Issue.record("unknown op")
                return
            }
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output), Swift \(actual)")
        }
    }
}

@Suite("Conformance: validation")
struct ValidationConformanceTests {
    @Test(arguments: Golden.cases("validation"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        try withDivergence(golden) {
            let input = golden.input
            func validationContext(_ raw: JSONValue) -> ValidationContext {
                let raw = Tagged.decode(raw)
                return ValidationContext(
                    value: raw["value"],
                    state: raw["state"].isUndefined ? [:] : raw["state"],
                    customFunctions: raw["custom"] == true ? Fixtures.validationFunctions : [:]
                )
            }
            func encode(_ result: ValidationCheckResult) -> JSONValue {
                ["type": result.type, "valid": .bool(result.valid), "message": result.message]
            }
            let actual: JSONValue
            switch input["op"].stringValue {
            case "builtin":
                actual = captureWithMessages {
                    let function = try #require(Validation.builtInFunctions[input["fn"].stringValue ?? ""])
                    return .bool(function(Tagged.decode(input["value"]), Tagged.decode(input["args"]).objectValue ?? [:]))
                }
            case "check":
                actual = captureWithMessages { encode(try Validation.runCheck(Tagged.decode(input["check"]), context: validationContext(input["context"]))) }
            case "run":
                actual = captureWithMessages {
                    let result = try Validation.run(Tagged.decode(input["config"]), context: validationContext(input["context"]))
                    return [
                        "valid": .bool(result.valid),
                        "errors": .array(JSONArray(result.errors)),
                        "checks": .array(JSONArray(result.checks.map(encode))),
                    ]
                }
            default:
                Issue.record("unknown op")
                return
            }
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output), Swift \(actual)")
        }
    }
}

@Suite("Conformance: spec validator")
struct SpecValidatorConformanceTests {
    @Test(arguments: Golden.cases("spec-validator"))
    func matchesUpstream(_ golden: GoldenCase) throws {
        try withDivergence(golden) {
            let input = golden.input
            let spec = Spec(Tagged.decode(input["spec"]).objectValue ?? [:])
            let options = Tagged.decode(input["options"])
            func encode(_ issue: SpecIssue) -> JSONValue {
                var object: JSONObject = ["severity": .string(issue.severity.rawValue), "message": .string(issue.message)]
                if let key = issue.elementKey { object["elementKey"] = .string(key) }
                object["code"] = .string(issue.code)
                return .object(object)
            }
            let actual: JSONValue
            switch input["op"].stringValue {
            case "validate":
                actual = Tagged.capture {
                    let result = try SpecValidator.validate(spec, checkOrphans: options["checkOrphans"] == true)
                    return ["valid": .bool(result.valid), "issues": .array(JSONArray(result.issues.map(encode)))]
                }
            case "autoFix":
                actual = Tagged.capture {
                    let result = try SpecValidator.autoFix(spec, lossy: options["lossy"] != false)
                    return [
                        "spec": .object(result.spec.object),
                        "fixes": .array(JSONArray(result.fixes.map(JSONValue.string))),
                        "fixDetails": .array(JSONArray(result.fixDetails.map { ["message": .string($0.message), "lossy": .bool($0.lossy)] })),
                    ]
                }
            case "format":
                actual = Tagged.capture {
                    let issues = (Tagged.decode(input["issues"]).arrayValue ?? []).map { issue in
                        SpecIssue(
                            severity: issue["severity"] == "warning" ? .warning : .error,
                            message: issue["message"].stringValue ?? "",
                            elementKey: issue["elementKey"].stringValue,
                            code: issue["code"].stringValue ?? ""
                        )
                    }
                    return .string(SpecValidator.formatIssues(issues))
                }
            default:
                Issue.record("unknown op")
                return
            }
            #expect(Tagged.matches(golden.output, actual), "upstream \(golden.output), Swift \(actual)")
        }
    }
}
