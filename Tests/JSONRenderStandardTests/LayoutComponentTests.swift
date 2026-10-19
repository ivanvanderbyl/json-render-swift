import JSONRender
import SwiftUI
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// The layout components of the React Native standard library
// (packages/react-native/src/components/standard.tsx). Upstream has no tests
// for them; these check each prop and default the upstream code applies.

@MainActor
@Suite("Standard layout components")
struct LayoutComponentTests {
    @Test("Container applies padding, margin, background, radius and flex")
    func container() throws {
        let model = try ContainerComponent.Model(render("Container", [
            "padding": 16, "paddingHorizontal": 8, "paddingVertical": nil, "margin": 4,
            "backgroundColor": "#FFFFFF", "borderRadius": 12, "flex": 1,
        ]).context)
        #expect(model.padding == EdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8))
        #expect(model.margin == 4)
        #expect(model.backgroundColor == .css("#ffffff"))
        #expect(model.borderRadius == 12)
        #expect(model.flex == 1)

        let empty = try ContainerComponent.Model(render("Container", [:]).context)
        #expect(empty.padding == EdgeInsets())
        #expect(empty.margin == 0)
        #expect(empty.backgroundColor == nil)
        #expect(empty.flex == nil)
    }

    @Test("Row lays out horizontally with gap, alignment, justification and wrap")
    func row() throws {
        let model = try RowComponent.Model(render("Row", [
            "gap": 12, "alignItems": "center", "justifyContent": "space-between", "flexWrap": "wrap", "padding": 4, "flex": 2,
        ]).context)
        #expect(model.layout == FlexLayout(axis: .horizontal, gap: 12, justify: .spaceBetween, align: .center, wraps: true))
        #expect(model.padding == 4)
        #expect(model.flex == 2)

        let plain = try RowComponent.Model(render("Row", [:]).context)
        #expect(plain.layout == FlexLayout(axis: .horizontal, gap: 0, justify: .flexStart, align: .stretch, wraps: false))
    }

    @Test("Column lays out vertically and has no wrap")
    func column() throws {
        let model = try ColumnComponent.Model(render("Column", [
            "gap": 8, "alignItems": "flex-end", "justifyContent": "space-evenly", "flexWrap": "wrap", "padding": nil,
        ]).context)
        #expect(model.layout == FlexLayout(axis: .vertical, gap: 8, justify: .spaceEvenly, align: .flexEnd, wraps: false))
        #expect(model.padding == 0)
    }

    @Test("ScrollContainer scrolls vertically and fills by default")
    func scrollContainer() throws {
        let plain = try ScrollContainerComponent.Model(render("ScrollContainer", [:]).context)
        #expect(plain.axis == .vertical)
        #expect(plain.showsIndicators)
        #expect(plain.flex == 1)

        let model = try ScrollContainerComponent.Model(render("ScrollContainer", [
            "horizontal": true, "showsScrollIndicator": false, "padding": 10, "backgroundColor": "red", "flex": 0,
        ]).context)
        #expect(model.axis == .horizontal)
        #expect(!model.showsIndicators)
        #expect(model.padding == 10)
        #expect(model.backgroundColor == .css("#ff0000"))
        #expect(model.flex == 0)
    }

    @Test("SafeArea fills the screen with an optional background")
    func safeArea() throws {
        #expect(try SafeAreaComponent.Model(render("SafeArea", ["backgroundColor": "#000"]).context).backgroundColor == .css("#000000"))
        #expect(try SafeAreaComponent.Model(render("SafeArea", [:]).context).backgroundColor == nil)
    }

    @Test("Spacer is a square of its size or flexible space")
    func spacer() throws {
        let fixed = try SpacerComponent.Model(render("Spacer", ["size": 24]).context)
        #expect(fixed.size == 24)
        #expect(fixed.flex == nil)
        let flexible = try SpacerComponent.Model(render("Spacer", ["size": nil, "flex": 1]).context)
        #expect(flexible.size == nil)
        #expect(flexible.flex == 1)
    }

    @Test("Pressable emits press and longPress")
    func pressable() async throws {
        let rendered = try render("Pressable", [:], on: events("press", "longPress"))
        let model = PressableComponent.Model(rendered.context)
        model.press()
        model.longPress()
        await rendered.runtime.settle()
        #expect(rendered.log.actions == ["press", "longPress"])
    }

    @Test("Divider is a thin line with upstream's colour, thickness and margin")
    func divider() throws {
        let horizontal = try DividerComponent.Model(render("Divider", [:]).context)
        #expect(!horizontal.isVertical)
        #expect(horizontal.thickness == 1)
        #expect(horizontal.color == .css("#e5e7eb"))
        #expect(horizontal.margin == 8)

        let vertical = try DividerComponent.Model(render("Divider", [
            "direction": "vertical", "color": "rgb(0, 0, 255)", "thickness": 2, "margin": 0,
        ]).context)
        #expect(vertical.isVertical)
        #expect(vertical.thickness == 2)
        #expect(vertical.color == .css("#0000ff"))
        #expect(vertical.margin == 0)
    }
}
