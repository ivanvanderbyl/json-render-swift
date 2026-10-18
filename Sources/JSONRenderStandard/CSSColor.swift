import SwiftUI

/// A colour from a React Native colour string: `#rgb`, `#rgba`, `#rrggbb`,
/// `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`, `hsla()`, a CSS colour name or
/// `transparent`. Components ignore strings that are not colours.
public struct CSSColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") {
            guard let color = Self.hex(text.dropFirst()) else { return nil }
            self = color
        } else if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let name = text[..<open].trimmingCharacters(in: .whitespaces)
            let body = text[text.index(after: open)..<text.index(before: text.endIndex)]
            guard let color = Self.functional(name, String(body)) else { return nil }
            self = color
        } else if text == "transparent" {
            self.init(red: 0, green: 0, blue: 0, opacity: 0)
        } else if let hex = Self.names[text], let color = Self.hex(Substring(hex)) {
            self = color
        } else {
            return nil
        }
    }

    /// The colour in SwiftUI.
    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }

    private static func hex(_ digits: Substring) -> CSSColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let values = digits.compactMap { $0.hexDigitValue }.map(Double.init)
        switch values.count {
        case 3, 4:
            let channels: [Double] = values.map { value in (value * 16 + value) / 255 }
            return CSSColor(red: channels[0], green: channels[1], blue: channels[2], opacity: channels.count == 4 ? channels[3] : 1)
        case 6, 8:
            let channels: [Double] = stride(from: 0, to: values.count, by: 2).map { index in
                let high: Double = values[index] * 16
                return (high + values[index + 1]) / 255
            }
            return CSSColor(red: channels[0], green: channels[1], blue: channels[2], opacity: channels.count == 4 ? channels[3] : 1)
        default:
            return nil
        }
    }

    /// `rgb(r, g, b)`, `rgb(r g b / a)`, `rgba(...)`, `hsl(...)` and `hsla(...)`.
    private static func functional(_ name: String, _ body: String) -> CSSColor? {
        var parts = body.replacingOccurrences(of: "/", with: " / ")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
        var alpha = 1.0
        if let slash = parts.firstIndex(of: "/") {
            guard slash == parts.count - 2, let value = component(parts[slash + 1], scale: 1) else { return nil }
            alpha = value
            parts.removeSubrange(slash...)
        } else if parts.count == 4 {
            guard let value = component(parts[3], scale: 1) else { return nil }
            alpha = value
            parts.removeLast()
        }
        guard parts.count == 3 else { return nil }
        switch name {
        case "rgb", "rgba":
            guard let r = component(parts[0], scale: 255), let g = component(parts[1], scale: 255), let b = component(parts[2], scale: 255) else { return nil }
            return CSSColor(red: r, green: g, blue: b, opacity: clamp(alpha))
        case "hsl", "hsla":
            guard let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                  parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
                  let saturation = Double(parts[1].dropLast()), let lightness = Double(parts[2].dropLast())
            else { return nil }
            let (r, g, b) = hslToRGB(hue, clamp(saturation / 100), clamp(lightness / 100))
            return CSSColor(red: r, green: g, blue: b, opacity: clamp(alpha))
        default:
            return nil
        }
    }

    /// A channel: a number out of `scale`, or a percentage.
    private static func component(_ text: String, scale: Double) -> Double? {
        if text.hasSuffix("%") { return Double(text.dropLast()).map { clamp($0 / 100) } }
        return Double(text).map { clamp($0 / scale) }
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func hslToRGB(_ hue: Double, _ saturation: Double, _ lightness: Double) -> (Double, Double, Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        func channel(_ n: Double) -> Double {
            let k = (n + h * 12).truncatingRemainder(dividingBy: 12)
            let a = saturation * min(lightness, 1 - lightness)
            return lightness - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return (channel(0), channel(8), channel(4))
    }

    /// The CSS named colours React Native accepts.
    private static let names: [String: String] = [
        "aliceblue": "f0f8ff", "antiquewhite": "faebd7", "aqua": "00ffff", "aquamarine": "7fffd4", "azure": "f0ffff",
        "beige": "f5f5dc", "bisque": "ffe4c4", "black": "000000", "blanchedalmond": "ffebcd", "blue": "0000ff",
        "blueviolet": "8a2be2", "brown": "a52a2a", "burlywood": "deb887", "cadetblue": "5f9ea0", "chartreuse": "7fff00",
        "chocolate": "d2691e", "coral": "ff7f50", "cornflowerblue": "6495ed", "cornsilk": "fff8dc", "crimson": "dc143c",
        "cyan": "00ffff", "darkblue": "00008b", "darkcyan": "008b8b", "darkgoldenrod": "b8860b", "darkgray": "a9a9a9",
        "darkgreen": "006400", "darkgrey": "a9a9a9", "darkkhaki": "bdb76b", "darkmagenta": "8b008b", "darkolivegreen": "556b2f",
        "darkorange": "ff8c00", "darkorchid": "9932cc", "darkred": "8b0000", "darksalmon": "e9967a", "darkseagreen": "8fbc8f",
        "darkslateblue": "483d8b", "darkslategray": "2f4f4f", "darkslategrey": "2f4f4f", "darkturquoise": "00ced1",
        "darkviolet": "9400d3", "deeppink": "ff1493", "deepskyblue": "00bfff", "dimgray": "696969", "dimgrey": "696969",
        "dodgerblue": "1e90ff", "firebrick": "b22222", "floralwhite": "fffaf0", "forestgreen": "228b22", "fuchsia": "ff00ff",
        "gainsboro": "dcdcdc", "ghostwhite": "f8f8ff", "gold": "ffd700", "goldenrod": "daa520", "gray": "808080",
        "green": "008000", "greenyellow": "adff2f", "grey": "808080", "honeydew": "f0fff0", "hotpink": "ff69b4",
        "indianred": "cd5c5c", "indigo": "4b0082", "ivory": "fffff0", "khaki": "f0e68c", "lavender": "e6e6fa",
        "lavenderblush": "fff0f5", "lawngreen": "7cfc00", "lemonchiffon": "fffacd", "lightblue": "add8e6",
        "lightcoral": "f08080", "lightcyan": "e0ffff", "lightgoldenrodyellow": "fafad2", "lightgray": "d3d3d3",
        "lightgreen": "90ee90", "lightgrey": "d3d3d3", "lightpink": "ffb6c1", "lightsalmon": "ffa07a",
        "lightseagreen": "20b2aa", "lightskyblue": "87cefa", "lightslategray": "778899", "lightslategrey": "778899",
        "lightsteelblue": "b0c4de", "lightyellow": "ffffe0", "lime": "00ff00", "limegreen": "32cd32", "linen": "faf0e6",
        "magenta": "ff00ff", "maroon": "800000", "mediumaquamarine": "66cdaa", "mediumblue": "0000cd",
        "mediumorchid": "ba55d3", "mediumpurple": "9370db", "mediumseagreen": "3cb371", "mediumslateblue": "7b68ee",
        "mediumspringgreen": "00fa9a", "mediumturquoise": "48d1cc", "mediumvioletred": "c71585", "midnightblue": "191970",
        "mintcream": "f5fffa", "mistyrose": "ffe4e1", "moccasin": "ffe4b5", "navajowhite": "ffdead", "navy": "000080",
        "oldlace": "fdf5e6", "olive": "808000", "olivedrab": "6b8e23", "orange": "ffa500", "orangered": "ff4500",
        "orchid": "da70d6", "palegoldenrod": "eee8aa", "palegreen": "98fb98", "paleturquoise": "afeeee",
        "palevioletred": "db7093", "papayawhip": "ffefd5", "peachpuff": "ffdab9", "peru": "cd853f", "pink": "ffc0cb",
        "plum": "dda0dd", "powderblue": "b0e0e6", "purple": "800080", "rebeccapurple": "663399", "red": "ff0000",
        "rosybrown": "bc8f8f", "royalblue": "4169e1", "saddlebrown": "8b4513", "salmon": "fa8072", "sandybrown": "f4a460",
        "seagreen": "2e8b57", "seashell": "fff5ee", "sienna": "a0522d", "silver": "c0c0c0", "skyblue": "87ceeb",
        "slateblue": "6a5acd", "slategray": "708090", "slategrey": "708090", "snow": "fffafa", "springgreen": "00ff7f",
        "steelblue": "4682b4", "tan": "d2b48c", "teal": "008080", "thistle": "d8bfd8", "tomato": "ff6347",
        "turquoise": "40e0d0", "violet": "ee82ee", "wheat": "f5deb3", "white": "ffffff", "whitesmoke": "f5f5f5",
        "yellow": "ffff00", "yellowgreen": "9acd32",
    ]
}
