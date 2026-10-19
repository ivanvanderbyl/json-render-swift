/// Whether `new URL(input)` succeeds, following the WHATWG URL Standard's
/// basic URL parser with no base URL.
///
/// Only the steps that can make parsing fail are implemented: scheme
/// detection, authorities of special schemes, hosts (IPv4, IPv6, opaque and
/// domain hosts) and ports. Domain names that contain non-ASCII characters
/// are accepted when every character is a letter, mark or digit; the full
/// UTS #46 mapping that browsers apply is not reproduced.
enum WHATWGURL {
    static func canParse(_ input: String) -> Bool {
        var scalars = Array(input.unicodeScalars)
        while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
        while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
        scalars.removeAll { $0 == "\t" || $0 == "\n" || $0 == "\r" }

        // Scheme.
        guard let first = scalars.first, isASCIIAlpha(first) else { return false }
        var index = 1
        while index < scalars.count, isASCIIAlphanumeric(scalars[index]) || "+-.".unicodeScalars.contains(scalars[index]) {
            index += 1
        }
        guard index < scalars.count, scalars[index] == ":" else { return false }
        let scheme = String(String.UnicodeScalarView(scalars[0..<index])).lowercased()
        let rest = Array(scalars[(index + 1)...])

        switch scheme {
        case "file":
            return parseFile(rest)
        case "http", "https", "ws", "wss", "ftp":
            var cursor = 0
            while cursor < rest.count, rest[cursor] == "/" || rest[cursor] == "\\" { cursor += 1 }
            return parseAuthority(Array(rest[cursor...]), special: true)
        default:
            if rest.count >= 2, rest[0] == "/", rest[1] == "/" {
                return parseAuthority(Array(rest[2...]), special: false)
            }
            return true
        }
    }

    private static func parseFile(_ rest: [Unicode.Scalar]) -> Bool {
        guard rest.count >= 2, rest[0] == "/" || rest[0] == "\\", rest[1] == "/" || rest[1] == "\\" else { return true }
        let afterSlashes = rest[2...]
        let end = afterSlashes.firstIndex { "/\\?#".unicodeScalars.contains($0) } ?? afterSlashes.endIndex
        let hostText = Array(afterSlashes[afterSlashes.startIndex..<end])
        if hostText.isEmpty { return true }
        // A Windows drive letter such as "C:" is a path, not a host.
        if hostText.count == 2, isASCIIAlpha(hostText[0]), hostText[1] == ":" || hostText[1] == "|" { return true }
        return parseHost(hostText, special: true) != nil
    }

    private static func parseAuthority(_ input: [Unicode.Scalar], special: Bool) -> Bool {
        let end = input.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" || (special && $0 == "\\") } ?? input.endIndex
        var authority = Array(input[..<end])
        if let at = authority.lastIndex(of: "@") {
            authority = Array(authority[(at + 1)...])
            if authority.isEmpty { return false }
        }
        // Split host and port on the last ":" outside brackets.
        var insideBrackets = false
        var colon: Int?
        for (position, scalar) in authority.enumerated() {
            if scalar == "[" { insideBrackets = true }
            if scalar == "]" { insideBrackets = false }
            if scalar == ":", !insideBrackets {
                colon = position
                break
            }
        }
        let hostText = colon.map { Array(authority[..<$0]) } ?? authority
        if let colon {
            if hostText.isEmpty { return false }
            let port = authority[(colon + 1)...]
            guard port.allSatisfy(isASCIIDigit) else { return false }
            if !port.isEmpty {
                let digits = String(String.UnicodeScalarView(port)).drop { $0 == "0" }
                if digits.count > 5 || (Int(digits) ?? 0) > 65535 { return false }
            }
        }
        if hostText.isEmpty { return !special }
        return parseHost(hostText, special: special) != nil
    }

    private static let forbiddenHost: Set<Unicode.Scalar> = [
        "\u{0}", "\t", "\n", "\r", " ", "#", "/", ":", "<", ">", "?", "@", "[", "\\", "]", "^", "|",
    ]

    /// The host parser. Returns nil on failure.
    private static func parseHost(_ input: [Unicode.Scalar], special: Bool) -> String? {
        if input.first == "[" {
            guard input.last == "]", input.count >= 2 else { return nil }
            return parseIPv6(Array(input[1..<(input.count - 1)])) ? "ipv6" : nil
        }
        if !special {
            return input.contains(where: forbiddenHost.contains) ? nil : "opaque"
        }
        guard let decoded = percentDecode(input) else { return nil }
        let domain = decoded.lowercased()
        for scalar in domain.unicodeScalars {
            if forbiddenHost.contains(scalar) || scalar.value < 0x20 || scalar == "%" || scalar.value == 0x7F { return nil }
            if !scalar.isASCII {
                let properties = scalar.properties
                guard properties.isAlphabetic || properties.numericType != nil
                    || properties.generalCategory == .nonspacingMark || properties.generalCategory == .spacingMark
                else { return nil }
            }
        }
        if domain.isEmpty { return nil }
        if endsInNumber(domain) { return parseIPv4(domain) ? "ipv4" : nil }
        return domain
    }

    private static func percentDecode(_ input: [Unicode.Scalar]) -> String? {
        var bytes: [UInt8] = []
        var index = 0
        while index < input.count {
            let scalar = input[index]
            if scalar == "%", index + 2 < input.count,
               let high = hexValue(input[index + 1]), let low = hexValue(input[index + 2]) {
                bytes.append(UInt8(high * 16 + low))
                index += 3
            } else {
                bytes.append(contentsOf: Array(String(scalar).utf8))
                index += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func endsInNumber(_ domain: String) -> Bool {
        var parts = domain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" {
            if parts.count == 1 { return false }
            parts.removeLast()
        }
        guard let last = parts.last, !last.isEmpty else { return false }
        if last.allSatisfy({ $0.isASCII && $0.isNumber }) { return true }
        return parseIPv4Number(last) != nil
    }

    private static func parseIPv4(_ domain: String) -> Bool {
        var parts = domain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "", parts.count > 1 { parts.removeLast() }
        guard parts.count <= 4 else { return false }
        var numbers: [Double] = []
        for part in parts {
            guard let number = parseIPv4Number(part) else { return false }
            numbers.append(number)
        }
        for number in numbers.dropLast() where number > 255 { return false }
        let limit = pow256(5 - numbers.count)
        return numbers.last! < limit
    }

    private static func pow256(_ exponent: Int) -> Double {
        (0..<exponent).reduce(1.0) { value, _ in value * 256 }
    }

    private static func parseIPv4Number(_ input: String) -> Double? {
        if input.isEmpty { return nil }
        var text = Substring(input)
        var radix = 10
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            radix = 16
            text = text.dropFirst(2)
        } else if text.count >= 2, text.hasPrefix("0") {
            radix = 8
            text = text.dropFirst()
        }
        if text.isEmpty { return 0 }
        var value = 0.0
        for character in text {
            guard let digit = character.hexDigitValue, character.isASCII, digit < radix else { return nil }
            value = value * Double(radix) + Double(digit)
        }
        return value
    }

    /// The IPv6 parser, reduced to a validity check.
    private static func parseIPv6(_ input: [Unicode.Scalar]) -> Bool {
        var pieceIndex = 0
        var compress: Int?
        var pointer = 0
        func at(_ offset: Int = 0) -> Unicode.Scalar? {
            pointer + offset < input.count ? input[pointer + offset] : nil
        }
        if at() == ":" {
            guard at(1) == ":" else { return false }
            pointer += 2
            pieceIndex += 1
            compress = pieceIndex
        }
        while at() != nil {
            if pieceIndex == 8 { return false }
            if at() == ":" {
                if compress != nil { return false }
                pointer += 1
                pieceIndex += 1
                compress = pieceIndex
                continue
            }
            var length = 0
            while length < 4, let scalar = at(), hexValue(scalar) != nil {
                pointer += 1
                length += 1
            }
            if at() == "." {
                if length == 0 { return false }
                pointer -= length
                if pieceIndex > 6 { return false }
                var numbersSeen = 0
                while at() != nil {
                    if numbersSeen > 0 {
                        if at() == ".", numbersSeen < 4 { pointer += 1 } else { return false }
                    }
                    guard let scalar = at(), isASCIIDigit(scalar) else { return false }
                    var value: Int?
                    while let digit = at(), isASCIIDigit(digit) {
                        let number = Int(digit.value - 0x30)
                        if value == nil {
                            value = number
                        } else if value == 0 {
                            return false
                        } else {
                            value = value! * 10 + number
                        }
                        if value! > 255 { return false }
                        pointer += 1
                    }
                    numbersSeen += 1
                    if numbersSeen == 2 || numbersSeen == 4 { pieceIndex += 1 }
                }
                if numbersSeen != 4 { return false }
                break
            } else if at() == ":" {
                pointer += 1
                if at() == nil { return false }
            } else if at() != nil {
                return false
            }
            pieceIndex += 1
        }
        if compress != nil {
            return pieceIndex != 8 || compress == nil ? pieceIndex <= 8 : false
        }
        return pieceIndex == 8
    }

    private static func hexValue(_ scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x30...0x39: Int(scalar.value - 0x30)
        case 0x41...0x46: Int(scalar.value - 0x41 + 10)
        case 0x61...0x66: Int(scalar.value - 0x61 + 10)
        default: nil
        }
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool { (0x30...0x39).contains(scalar.value) }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIAlpha(scalar) || isASCIIDigit(scalar)
    }
}
