#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Foundation
import JSONRender
import JSONRenderUI
import SwiftUI
import Testing

// Brightfield's Brie surfaces are the first consumer of the renderer. The
// fixture is brie-v1.schema.json from the Brightfield mobile app
// (packages/genui), generated with zod's toJSONSchema from its json-render
// 0.21.1 catalog. Everything Brightfield-specific lives in this test: the
// library only loads the exported schema and draws host-registered views.

/// Draws a view and lays it out so every body runs: an NSHostingView on
/// macOS, and a UIHostingController in a window on iOS.
@MainActor
final class Host<Content: View> {
    #if canImport(UIKit)
    let controller: UIHostingController<Content>
    let window: UIWindow

    init(_ content: Content, width: CGFloat = 400, height: CGFloat = 800) {
        controller = UIHostingController(rootView: content)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        layout()
    }

    func update(_ content: Content) {
        controller.rootView = content
        layout()
    }

    func layout() {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
    #else
    let view: NSHostingView<Content>

    init(_ content: Content, width: CGFloat = 400, height: CGFloat = 800) {
        view = NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
    }

    func update(_ content: Content) {
        view.rootView = content
        layout()
    }

    func layout() { view.layoutSubtreeIfNeeded() }
    #endif
}

@MainActor
@Suite("Brie surfaces")
struct BrieSurfaceTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func loadSchema() throws -> SpecJSONSchema {
        try SpecJSONSchema(JSONValue(parsing: Data(contentsOf: fixtures.appendingPathComponent("brie-v1.schema.json"))))
    }

    nonisolated static func surface(_ elements: JSONObject, root: String = "stack", catalog: String = "brightfield.brie/v1") -> JSONValue {
        ["catalog": .string(catalog), "spec": ["root": .string(root), "elements": .object(elements)]]
    }

    nonisolated static let fixed: JSONObject = ["componentId": "position", "revision": "1"]

    @Test("the exported schema lists every Brie card")
    func listsCards() throws {
        let schema = try Self.loadSchema()
        #expect(schema.specPath == ["spec"])
        #expect(schema.componentNames == [
            "Stack", "CountryPicker", "ConnectBank", "ConnectionResult", "BuildProgress", "Strengths",
            "WhereYouStand", "Finding", "Figures", "Receipt", "AllSet", "Question", "Approval",
            "HelpAnswer", "FollowUpChips",
        ])
    }

    @Test("accepts the README surface")
    func acceptsReadmeSurface() throws {
        let surface = Self.surface(["position": ["type": "WhereYouStand", "props": .object(Self.fixed), "children": []]], root: "position")
        let schema = try Self.loadSchema()
        #expect(schema.validate(surface).success)
        #expect(schema.spec(in: surface)?.root == "position")
    }

    @Test("rejects surfaces outside the catalog", arguments: [
        ("another catalog version", surface(["s": ["type": "Stack", "props": [:], "children": []]], root: "s", catalog: "brightfield.brie/v2")),
        ("a prop the card does not take", surface(["c": ["type": "Finding", "props": ["componentId": "a", "revision": "1", "amount": 10], "children": []]], root: "c")),
        ("a revision with a leading zero", surface(["c": ["type": "Finding", "props": ["componentId": "a", "revision": "01"], "children": []]], root: "c")),
        ("children on a fixed card", surface(["c": ["type": "Figures", "props": .object(fixed), "children": ["x"]]], root: "c")),
        ("an unknown card", surface(["c": ["type": "Chart", "props": [:], "children": []]], root: "c")),
        ("a missing children list", surface(["c": ["type": "Question", "props": ["questionKey": "turn-1:call-1"]]], root: "c")),
        ("an empty reference", surface(["c": ["type": "HelpAnswer", "props": ["resultId": ""], "children": []]], root: "c")),
        ("more than 32 cards in a stack", surface(["s": ["type": "Stack", "props": [:], "children": .array(JSONArray((0...32).map { .string("c\($0)") }))]], root: "s")),
    ])
    func rejects(reason: String, surface: JSONValue) throws {
        #expect(!(try Self.loadSchema().validate(surface).success), "should reject \(reason)")
    }

    @Test("draws a stack of cards with host views and an unavailable card for the rest")
    func drawsHostViews() throws {
        let schema = try Self.loadSchema()
        let surface = Self.surface([
            "stack": ["type": "Stack", "props": [:], "children": ["position", "question", "help"]],
            "position": ["type": "WhereYouStand", "props": .object(Self.fixed), "children": []],
            "question": ["type": "Question", "props": ["questionKey": "turn-1:call-1"], "children": []],
            "help": ["type": "HelpAnswer", "props": ["resultId": "turn-1:call-2"], "children": []],
        ])
        let spec = try #require(schema.spec(in: surface))

        var drawn: [String] = []
        let unavailable = Component { context in
            let _ = drawn.append("unavailable \(context.element.type.javaScriptString)")
            Text("This card is not available in this client yet.")
        }
        var components = Dictionary(uniqueKeysWithValues: schema.componentNames.map { ($0, unavailable) })
        components["Stack"] = Component { context in VStack { context.children } }
        components["WhereYouStand"] = Component { context in
            let _ = drawn.append("position \(context.props["componentId"]?.stringValue ?? "") r\(context.props["revision"]?.stringValue ?? "")")
            Text("Where you stand")
        }
        components["Question"] = Component { context in
            let _ = drawn.append("question \(context.props["questionKey"]?.stringValue ?? "")")
            Text("Question")
        }
        let registry = Registry(catalog: schema.catalog(), components: components)

        _ = Host(Renderer(spec: spec, registry: registry, runtime: Runtime()), width: 390, height: 600)

        #expect(drawn == ["position position r1", "question turn-1:call-1", "unavailable HelpAnswer"])
    }
}
