/// JavaScript language operations that json-render relies on, implemented to
/// the ECMAScript specification so Swift produces the same strings, numbers
/// and comparisons as the upstream TypeScript code.
enum JavaScript {
    // MARK: Number to string

    /// `Number.prototype.toString()` with radix 10 (ECMAScript Number::toString).
    static func numberToString(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == 0 { return "0" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        if value < 0 { return "-" + numberToString(-value) }

        // Swift's description gives the shortest round-tripping digits, which is
        // the digit string ECMAScript requires. Reformat it with ECMAScript rules.
        let (digits, exponent) = shortestDigits(value)
        let k = digits.count
        let n = exponent
        if k <= n && n <= 21 {
            return digits + String(repeating: "0", count: n - k)
        }
        if 0 < n && n <= 21 {
            let split = digits.index(digits.startIndex, offsetBy: n)
            return digits[..<split] + "." + digits[split...]
        }
        if -6 < n && n <= 0 {
            return "0." + String(repeating: "0", count: -n) + digits
        }
        let sign = n - 1 < 0 ? "-" : "+"
        let magnitude = String(abs(n - 1))
        if k == 1 { return digits + "e" + sign + magnitude }
        return String(digits.first!) + "." + digits.dropFirst() + "e" + sign + magnitude
    }

    /// The shortest digits `d` and exponent `n` with value = 0.d × 10^n.
    private static func shortestDigits(_ value: Double) -> (String, Int) {
        let text = value.description
        var mantissa = Substring(text)
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = text[..<e]
            exponent = Int(text[text.index(after: e)...])!
        }
        var integerPart = mantissa
        var fractionPart: Substring = ""
        if let dot = mantissa.firstIndex(of: ".") {
            integerPart = mantissa[..<dot]
            fractionPart = mantissa[mantissa.index(after: dot)...]
        }
        var digits = Array(integerPart + fractionPart)
        var pointPosition = integerPart.count + exponent
        while digits.first == "0" {
            digits.removeFirst()
            pointPosition -= 1
        }
        while digits.last == "0" { digits.removeLast() }
        return (String(digits), pointPosition)
    }

    // MARK: String to number

    /// `Number(string)`: ECMAScript StringToNumber.
    static func stringToNumber(_ string: String) -> Double {
        let trimmed = trim(string)
        if trimmed.isEmpty { return 0 }
        let units = Array(trimmed.utf16)
        if units.count > 2, units[0] == 0x30 {
            let radix: Int? = switch units[1] {
            case 0x78, 0x58: 16
            case 0x6F, 0x4F: 8
            case 0x62, 0x42: 2
            default: nil
            }
            if let radix { return parseInteger(units.dropFirst(2), radix: radix) }
        }
        var body = Substring(trimmed)
        var sign = 1.0
        if body.first == "+" || body.first == "-" {
            sign = body.first == "-" ? -1 : 1
            body = body.dropFirst()
        }
        if body == "Infinity" { return sign * .infinity }
        guard isDecimalLiteral(body), let magnitude = Double(String(body)) else { return .nan }
        return sign * magnitude
    }

    private static func parseInteger(_ units: ArraySlice<UInt16>, radix: Int) -> Double {
        var value = 0.0
        for unit in units {
            let digit: Int
            switch unit {
            case 0x30...0x39: digit = Int(unit - 0x30)
            case 0x61...0x7A: digit = Int(unit - 0x61) + 10
            case 0x41...0x5A: digit = Int(unit - 0x41) + 10
            default: return .nan
            }
            guard digit < radix else { return .nan }
            value = value * Double(radix) + Double(digit)
        }
        return value
    }

    /// StrUnsignedDecimalLiteral without "Infinity": digits with an optional
    /// fraction and exponent, at least one digit in the significand.
    private static func isDecimalLiteral(_ text: Substring) -> Bool {
        var index = text.startIndex
        var significandDigits = 0
        func isDigit(_ character: Character) -> Bool { character >= "0" && character <= "9" && character.isASCII }
        while index < text.endIndex, isDigit(text[index]) {
            significandDigits += 1
            index = text.index(after: index)
        }
        if index < text.endIndex, text[index] == "." {
            index = text.index(after: index)
            while index < text.endIndex, isDigit(text[index]) {
                significandDigits += 1
                index = text.index(after: index)
            }
        }
        guard significandDigits > 0 else { return false }
        if index < text.endIndex, text[index] == "e" || text[index] == "E" {
            index = text.index(after: index)
            if index < text.endIndex, text[index] == "+" || text[index] == "-" { index = text.index(after: index) }
            var exponentDigits = 0
            while index < text.endIndex, isDigit(text[index]) {
                exponentDigits += 1
                index = text.index(after: index)
            }
            guard exponentDigits > 0 else { return false }
        }
        return index == text.endIndex
    }

    // MARK: Strings

    /// `String.prototype.trim()`: removes ECMAScript WhiteSpace and
    /// LineTerminator code points from both ends.
    static func trim(_ string: String) -> String {
        let scalars = string.unicodeScalars
        guard let start = scalars.firstIndex(where: { !isWhitespace($0) }) else { return "" }
        let end = scalars.lastIndex(where: { !isWhitespace($0) })!
        return String(scalars[start...end])
    }

    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            true
        default:
            false
        }
    }

    /// `string.length`: the number of UTF-16 code units.
    static func length(_ string: String) -> Int { string.utf16.count }

    /// `a < b` for two strings: lexicographic order of UTF-16 code units.
    static func lessThan(_ a: String, _ b: String) -> Bool {
        a.utf16.lexicographicallyPrecedes(b.utf16)
    }

    /// QuoteJSONString from `JSON.stringify`.
    static func quoteJSONString(_ string: String, into output: inout String) {
        output += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if scalar.value < 0x20 {
                    output += "\\u" + String(repeating: "0", count: 4 - String(scalar.value, radix: 16).count)
                        + String(scalar.value, radix: 16)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
    }
}
