import Testing

/// Corpus cases where the Swift port knowingly differs from upstream, with the
/// reason. Each is listed in COMPATIBILITY.md. A listed case runs inside
/// `withKnownIssue`, so it fails if it ever starts to match (the entry is then
/// stale and must be removed).
enum Divergences {
    static let reasons: [String: [String: String]] = [
        "paths": [
            "get: prototype-like key":
                "JavaScript objects inherit Object.prototype members such as toString; JSON values have no prototype.",
        ],
        "schemas": [
            "array min equals max #0":
                "z.array().min(n).max(n) and .length(n) export the same JSON Schema; the import reads equal bounds as .length(n), so only the message differs.",
            "string min equals max #0":
                "z.string().min(n).max(n) and .length(n) export the same JSON Schema; the import reads equal bounds as .length(n), so only the message differs.",
            "regex then min #0":
                "The export lists minLength before pattern whatever the zod chain order, so the two issues come out in the other order.",
            "optional #0":
                "JSON Schema cannot mark a top-level schema optional, so an imported schema rejects undefined where z.optional() accepts it. JSON input never contains undefined.",
        ],
        "validation": [
            "builtin pattern: astral dot":
                "ECMAScript regular expressions without the u flag match UTF-16 code units; NSRegularExpression matches code points.",
            "builtin pattern: astral two dots":
                "ECMAScript regular expressions without the u flag match UTF-16 code units; NSRegularExpression matches code points.",
        ],
    ]
}

/// Runs a conformance check, expecting failure for a documented divergence.
/// Suites that check several values per case name them "<case> #<index>".
func withDivergence(_ golden: GoldenCase, value index: Int? = nil, _ body: () throws -> Void) rethrows {
    let name = index.map { "\(golden.name) #\($0)" } ?? golden.name
    if let reason = Divergences.reasons[golden.suite]?[name] {
        withKnownIssue(Comment(rawValue: reason)) { try body() }
    } else {
        try body()
    }
}
