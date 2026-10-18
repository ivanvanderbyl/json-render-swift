#if canImport(AppKit)
import AppKit
import JSONRender
import SwiftUI
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

/// Draws every standard component through SwiftUI. Laying out the hosting
/// view runs every component body, so a component that cannot draw its
/// props shows up as a failed node.
@MainActor
@Suite("Standard components in SwiftUI")
struct StandardRenderingTests {
    @Test("every standard component draws its props")
    func everyComponentDraws() async throws {
        let elements: JSONObject = [
            "screen": ["type": "SafeArea", "props": ["backgroundColor": "#fafafa"], "children": ["scroll"]],
            "scroll": ["type": "ScrollContainer", "props": ["padding": 16], "children": ["column"]],
            "column": ["type": "Column", "props": ["gap": 12], "children": [
                "container", "row", "heading", "paragraph", "label", "image", "avatar", "badge", "chip",
                "button", "input", "switch", "checkbox", "slider", "search", "spinner", "progress", "card", "list", "modal",
            ]],
            "container": ["type": "Container", "props": ["padding": 8, "backgroundColor": "rgba(0,0,0,0.05)", "borderRadius": 8], "children": ["spacer", "divider"]],
            "spacer": ["type": "Spacer", "props": ["size": 8]],
            "divider": ["type": "Divider", "props": [:]],
            "row": ["type": "Row", "props": ["gap": 8, "justifyContent": "space-between", "flexWrap": "wrap", "alignItems": "center"], "children": ["pressable", "pressable-2"]],
            "pressable": ["type": "Pressable", "props": [:], "children": ["pressable-label"], "on": ["press": ["action": "setState", "params": ["statePath": "/pressed", "value": true]]]],
            "pressable-label": ["type": "Label", "props": ["text": "Press"]],
            "pressable-2": ["type": "Label", "props": ["text": "Beside", "bold": true]],
            "heading": ["type": "Heading", "props": ["text": "Welcome", "level": "h1", "align": "center"]],
            "paragraph": ["type": "Paragraph", "props": ["text": "Body text", "numberOfLines": 2]],
            "label": ["type": "Label", "props": ["text": "Status", "size": "xs"]],
            "image": ["type": "Image", "props": ["src": "https://example.com/a.png", "alt": "A", "height": 100, "resizeMode": "contain"]],
            "avatar": ["type": "Avatar", "props": ["initials": "JD", "size": "lg"]],
            "badge": ["type": "Badge", "props": ["label": "New", "variant": "success"]],
            "chip": ["type": "Chip", "props": ["label": "Tag", "selected": true], "on": ["remove": ["action": "setState", "params": ["statePath": "/chip", "value": nil]]]],
            "button": ["type": "Button", "props": ["label": "Save", "variant": "outline", "loading": true]],
            "input": ["type": "TextInput", "props": ["label": "Name", "value": ["$bindState": "/name"], "multiline": true]],
            "switch": ["type": "Switch", "props": ["label": "On", "checked": ["$bindState": "/on"]]],
            "checkbox": ["type": "Checkbox", "props": ["label": "Agree", "checked": true]],
            "slider": ["type": "Slider", "props": ["label": "Volume", "value": 30]],
            "search": ["type": "SearchBar", "props": ["placeholder": "Find"]],
            "spinner": ["type": "Spinner", "props": ["size": "large"]],
            "progress": ["type": "ProgressBar", "props": ["progress": 0.5]],
            "card": ["type": "Card", "props": ["title": "Card", "subtitle": "Sub"], "children": ["list-in-card"]],
            "list-in-card": ["type": "ListItem", "props": ["title": "Inside", "showChevron": true]],
            "list": ["type": "ListItem", "props": ["title": "Row", "leading": "*", "trailing": "On"], "on": ["press": ["action": "setState", "params": ["statePath": "/row", "value": 1]]]],
            "modal": ["type": "Modal", "props": ["visible": false, "title": "Modal"], "children": []],
        ]
        let runtime = Runtime(initialState: ["name": "Ada", "on": true])
        let view = NSHostingView(rootView: Renderer(spec: Spec(root: "screen", elements: elements), registry: .standard, runtime: runtime))
        view.frame = NSRect(x: 0, y: 0, width: 390, height: 2000)
        view.layoutSubtreeIfNeeded()
        await runtime.settle()
        view.layoutSubtreeIfNeeded()

        let tree = try #require(runtime.tree)
        let failed = tree.allNodes.filter { $0.status != .rendered }.map(\.id)
        #expect(failed.isEmpty)
        #expect(tree.allNodes.count == elements.count)
    }
}
#endif
