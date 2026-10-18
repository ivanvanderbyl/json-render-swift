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
        "validation": [
            "builtin pattern: astral dot":
                "ECMAScript regular expressions without the u flag match UTF-16 code units; NSRegularExpression matches code points.",
            "builtin pattern: astral two dots":
                "ECMAScript regular expressions without the u flag match UTF-16 code units; NSRegularExpression matches code points.",
        ],
    ]
}

/// Runs a conformance check, expecting failure for a documented divergence.
func withDivergence(_ golden: GoldenCase, _ body: () throws -> Void) rethrows {
    if let reason = Divergences.reasons[golden.suite]?[golden.name] {
        withKnownIssue(Comment(rawValue: reason)) { try body() }
    } else {
        try body()
    }
}
