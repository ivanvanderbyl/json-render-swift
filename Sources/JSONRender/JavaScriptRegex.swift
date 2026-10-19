import Foundation

/// `new RegExp(source)` without flags, run on NSRegularExpression.
///
/// ICU and ECMAScript regular expressions differ in a few places that change
/// results for ordinary patterns. The source is rewritten so that:
///
/// - `$` matches only at the end of input (ICU also matches before a final
///   line terminator).
/// - `.` excludes only \n, \r, U+2028 and U+2029 (ICU also excludes U+0085).
/// - `\d`, `\w` and `\b` are ASCII-only, and `\s` is the ECMAScript whitespace
///   set, rather than their Unicode ICU meanings.
/// - `[^]` matches any character and `[]` matches nothing.
/// - A `{` that does not start a quantifier is a literal, as in Annex B.
///
/// Remaining differences: ECMAScript without the `u` flag matches UTF-16 code
/// units, so `.` matches half of an astral character there and a whole
/// character here; and rarely used Annex B forms (such as `\c` outside the
/// letter range) are not translated.
struct JavaScriptRegex {
    let expression: NSRegularExpression

    init?(_ source: String) {
        guard let translated = Self.translate(source),
              let expression = try? NSRegularExpression(pattern: translated)
        else { return nil }
        self.expression = expression
    }

    /// `regex.test(string)`.
    func test(_ string: String) -> Bool {
        expression.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    private static let whitespace = #"\t\n\u000B\f\r    -     　﻿"#
    private static let word = "A-Za-z0-9_"
    private static let wordBoundary = "(?:(?<=[A-Za-z0-9_])(?![A-Za-z0-9_])|(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]))"
    private static let notWordBoundary = "(?:(?<=[A-Za-z0-9_])(?=[A-Za-z0-9_])|(?<![A-Za-z0-9_])(?![A-Za-z0-9_]))"

    static func translate(_ source: String) -> String? {
        let characters = Array(source)
        var output = ""
        var index = 0
        var inClass = false
        var classStart = 0

        func isQuantifierBrace(at position: Int) -> Bool {
            var cursor = position + 1
            var digits = 0
            while cursor < characters.count, characters[cursor].isASCII, characters[cursor].isNumber {
                digits += 1
                cursor += 1
            }
            guard digits > 0, cursor < characters.count else { return false }
            if characters[cursor] == "," {
                cursor += 1
                while cursor < characters.count, characters[cursor].isASCII, characters[cursor].isNumber { cursor += 1 }
            }
            return cursor < characters.count && characters[cursor] == "}"
        }

        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                guard index + 1 < characters.count else { return nil }
                let escaped = characters[index + 1]
                index += 2
                switch escaped {
                case "d": output += inClass ? "0-9" : "[0-9]"
                case "D": output += inClass ? "[^0-9]" : "[^0-9]"
                case "w": output += inClass ? word : "[\(word)]"
                case "W": output += "[^\(word)]"
                case "s": output += inClass ? whitespace : "[\(whitespace)]"
                case "S": output += "[^\(whitespace)]"
                case "b": output += inClass ? "\\u0008" : wordBoundary
                case "B": output += inClass ? "B" : notWordBoundary
                default: output += "\\" + String(escaped)
                }
                continue
            }
            if inClass {
                if character == "]" {
                    inClass = false
                    output += "]"
                } else if character == "[" {
                    output += "\\["
                } else {
                    output.append(character)
                }
                index += 1
                continue
            }
            switch character {
            case "[":
                if index + 2 < characters.count + 1, index + 1 < characters.count, characters[index + 1] == "]" {
                    output += "(?!)"
                    index += 2
                    continue
                }
                if index + 2 < characters.count, characters[index + 1] == "^", characters[index + 2] == "]" {
                    output += "(?s:.)"
                    index += 3
                    continue
                }
                inClass = true
                classStart = index
                output += "["
                if index + 1 < characters.count, characters[index + 1] == "^" {
                    output += "^"
                    index += 1
                }
                // A leading "]" closes nothing in ICU either way; JavaScript
                // treats "[]" as empty, handled above.
            case "$":
                output += "\\z"
            case ".":
                output += "[^\\n\\r\\u2028\\u2029]"
            case "{":
                output += isQuantifierBrace(at: index) ? "{" : "\\{"
            case "}":
                // A "}" that does not close a quantifier is literal in Annex B.
                output += quantifierCloses(characters, at: index) ? "}" : "\\}"
            default:
                output.append(character)
            }
            index += 1
        }
        _ = classStart
        return inClass ? nil : output
    }

    /// True when the `}` at `position` closes a `{n}`, `{n,}` or `{n,m}` quantifier.
    private static func quantifierCloses(_ characters: [Character], at position: Int) -> Bool {
        var cursor = position - 1
        var sawDigit = false
        while cursor >= 0, characters[cursor].isASCII, characters[cursor].isNumber || characters[cursor] == "," {
            if characters[cursor].isNumber { sawDigit = true }
            cursor -= 1
        }
        return sawDigit && cursor >= 0 && characters[cursor] == "{"
    }
}
