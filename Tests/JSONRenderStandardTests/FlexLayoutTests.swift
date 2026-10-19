import SwiftUI
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// The flexbox subset the Row, Column and Container components use, solved
// without SwiftUI so the arithmetic can be checked.

@Suite("Flex layout")
struct FlexLayoutTests {
    /// An item with a fixed size.
    func fixed(_ width: Double, _ height: Double) -> FlexItem {
        FlexItem(flex: 0) { _ in CGSize(width: width, height: height) }
    }

    /// An item that grows to fill what it is offered.
    func growing(_ flex: Double, height: Double = 10) -> FlexItem {
        FlexItem(flex: flex) { proposal in CGSize(width: proposal.width ?? 0, height: height) }
    }

    func origins(_ layout: FlexLayout, _ items: [FlexItem], in size: CGSize) -> [CGPoint] {
        layout.frames(for: items, in: CGRect(origin: .zero, size: size)).map(\.origin)
    }

    @Test("a row places items side by side with the gap")
    func rowWithGap() {
        let layout = FlexLayout(axis: .horizontal, gap: 10, justify: .flexStart, align: .flexStart, wraps: false)
        let items = [fixed(50, 20), fixed(30, 40)]
        #expect(layout.size(for: items, proposal: ProposedViewSize(width: nil, height: nil)) == CGSize(width: 90, height: 40))
        #expect(origins(layout, items, in: CGSize(width: 90, height: 40)) == [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0)])
    }

    @Test("justifyContent distributes free space", arguments: [
        (FlexJustify.flexStart, [0.0, 50.0]), (.flexEnd, [120.0, 170.0]), (.center, [60.0, 110.0]),
        (.spaceBetween, [0.0, 170.0]), (.spaceAround, [30.0, 140.0]), (.spaceEvenly, [40.0, 130.0]),
    ])
    func justify(justify: FlexJustify, xs: [Double]) {
        let layout = FlexLayout(axis: .horizontal, gap: 0, justify: justify, align: .flexStart, wraps: false)
        let items = [fixed(50, 10), fixed(30, 10)]
        #expect(origins(layout, items, in: CGSize(width: 200, height: 10)).map(\.x) == xs.map { CGFloat($0) })
    }

    @Test("alignItems positions items across the axis", arguments: [
        (FlexAlign.flexStart, 0.0), (.center, 15.0), (.flexEnd, 30.0), (.stretch, 0.0),
    ])
    func align(align: FlexAlign, y: Double) {
        let layout = FlexLayout(axis: .horizontal, gap: 0, justify: .flexStart, align: align, wraps: false)
        let items = [fixed(50, 10), fixed(50, 40)]
        #expect(origins(layout, items, in: CGSize(width: 100, height: 40)).first?.y == CGFloat(y))
    }

    @Test("stretched items are offered the full cross size")
    func stretch() {
        let layout = FlexLayout(axis: .vertical, gap: 0, justify: .flexStart, align: .stretch, wraps: false)
        let item = FlexItem(flex: 0) { proposal in CGSize(width: proposal.width ?? 10, height: 10) }
        let frames = layout.frames(for: [item], in: CGRect(x: 0, y: 0, width: 300, height: 100))
        #expect(frames.first?.width == 300)
    }

    @Test("flex items share the remaining space by their flex")
    func flexGrow() {
        let layout = FlexLayout(axis: .horizontal, gap: 10, justify: .flexStart, align: .flexStart, wraps: false)
        let items = [fixed(40, 10), growing(1), growing(3)]
        let frames = layout.frames(for: items, in: CGRect(x: 0, y: 0, width: 220, height: 10))
        #expect(frames.map(\.minX) == [0, 50, 100])
        #expect(frames.map(\.width) == [40, 40, 120])
    }

    @Test("a wrapping row moves items that do not fit to the next line")
    func wrap() {
        let layout = FlexLayout(axis: .horizontal, gap: 10, justify: .flexStart, align: .flexStart, wraps: true)
        let items = [fixed(60, 20), fixed(60, 30), fixed(60, 20)]
        #expect(layout.size(for: items, proposal: ProposedViewSize(width: 150, height: nil)) == CGSize(width: 150, height: 60))
        #expect(origins(layout, items, in: CGSize(width: 150, height: 60)) == [
            CGPoint(x: 0, y: 0), CGPoint(x: 70, y: 0), CGPoint(x: 0, y: 40),
        ])
    }

    @Test("a column stacks items and fills its offered width")
    func column() {
        let layout = FlexLayout(axis: .vertical, gap: 8, justify: .flexStart, align: .flexStart, wraps: false)
        let items = [fixed(50, 20), fixed(30, 40)]
        #expect(layout.size(for: items, proposal: ProposedViewSize(width: 200, height: nil)) == CGSize(width: 200, height: 68))
        #expect(origins(layout, items, in: CGSize(width: 200, height: 68)) == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 28)])
    }
}
