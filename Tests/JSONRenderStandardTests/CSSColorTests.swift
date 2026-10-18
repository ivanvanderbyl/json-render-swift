import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// React Native colour strings: hex, rgb(a), hsl(a), named colours and
// "transparent".

@Suite("CSS colours")
struct CSSColorTests {
    @Test("hex forms", arguments: [
        ("#f00", CSSColor(red: 1, green: 0, blue: 0)),
        ("#f008", CSSColor(red: 1, green: 0, blue: 0, opacity: 0x88 / 255)),
        ("#00FF00", CSSColor(red: 0, green: 1, blue: 0)),
        ("#0000ff80", CSSColor(red: 0, green: 0, blue: 1, opacity: 0x80 / 255)),
    ])
    func hex(text: String, color: CSSColor) {
        #expect(CSSColor(text) == color)
    }

    @Test("functional forms")
    func functional() {
        #expect(CSSColor("rgb(255, 0, 0)") == CSSColor(red: 1, green: 0, blue: 0))
        #expect(CSSColor("rgba(0, 0, 0, 0.5)") == CSSColor(red: 0, green: 0, blue: 0, opacity: 0.5))
        #expect(CSSColor("rgb(0 0 255 / 50%)") == CSSColor(red: 0, green: 0, blue: 1, opacity: 0.5))
        #expect(CSSColor("hsl(120, 100%, 50%)") == CSSColor(red: 0, green: 1, blue: 0))
        #expect(CSSColor("hsla(0, 100%, 50%, 0.25)") == CSSColor(red: 1, green: 0, blue: 0, opacity: 0.25))
    }

    @Test("names, transparent and case")
    func names() {
        #expect(CSSColor("red") == CSSColor(red: 1, green: 0, blue: 0))
        #expect(CSSColor("RebeccaPurple") == CSSColor("#663399"))
        #expect(CSSColor(" white ") == CSSColor(red: 1, green: 1, blue: 1))
        #expect(CSSColor("transparent") == CSSColor(red: 0, green: 0, blue: 0, opacity: 0))
    }

    @Test("invalid strings are not colours", arguments: ["", "#12", "#ggg", "rgb(1, 2)", "notacolour", "#12345"])
    func invalid(text: String) {
        #expect(CSSColor(text) == nil)
    }
}
