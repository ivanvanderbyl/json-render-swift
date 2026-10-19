import Foundation
import Testing
@testable import JSONRender

/// One corpus case paired with the output upstream json-render produced for it.
struct GoldenCase: Sendable, CustomTestStringConvertible {
    let suite: String
    let name: String
    /// The corpus entry, with tagged values still encoded.
    let input: JSONValue
    /// The upstream output, with tagged values still encoded.
    let output: JSONValue

    var testDescription: String { name }
}

/// Loads `Conformance/corpus/<suite>.json` and `Conformance/goldens/<suite>.json`.
enum Golden {
    static let conformanceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // ConformanceTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root
        .appendingPathComponent("Conformance")

    static func read(_ relativePath: String) throws -> JSONValue {
        let url = conformanceDirectory.appendingPathComponent(relativePath)
        return try JSONValue(parsing: Data(contentsOf: url))
    }

    /// The cases of a suite. A missing or unreadable golden is a test failure,
    /// reported through a single placeholder case so the suite still runs.
    static func cases(_ suite: String) -> [GoldenCase] {
        do {
            let corpus = try read("corpus/\(suite).json")
            let golden = try read("goldens/\(suite).json")
            let outputs = Dictionary(
                (golden["cases"].arrayValue ?? []).map { ($0["name"].stringValue ?? "", $0["output"]) },
                uniquingKeysWith: { first, _ in first }
            )
            return (corpus["cases"].arrayValue ?? []).map { entry in
                let name = entry["name"].stringValue ?? "?"
                return GoldenCase(suite: suite, name: name, input: entry, output: outputs[name] ?? .undefined)
            }
        } catch {
            return [GoldenCase(suite: suite, name: "unreadable: \(error)", input: .undefined, output: .undefined)]
        }
    }
}
