import SwiftUI

/// `justifyContent`: where items sit along the main axis.
public enum FlexJustify: String, Sendable, CaseIterable {
    case flexStart = "flex-start"
    case center
    case flexEnd = "flex-end"
    case spaceBetween = "space-between"
    case spaceAround = "space-around"
    case spaceEvenly = "space-evenly"
}

/// `alignItems`: where items sit across the main axis.
public enum FlexAlign: String, Sendable, CaseIterable {
    case flexStart = "flex-start"
    case center
    case flexEnd = "flex-end"
    case stretch
    case baseline
}

/// One item for ``FlexLayout``'s solver: how it sizes itself and its `flex`.
public struct FlexItem {
    public var flex: Double
    /// The distance from the item's top to its first text baseline.
    public var baseline: (ProposedViewSize) -> CGFloat?
    public var measure: (ProposedViewSize) -> CGSize

    public init(flex: Double, baseline: @escaping (ProposedViewSize) -> CGFloat? = { _ in nil }, measure: @escaping (ProposedViewSize) -> CGSize) {
        self.flex = flex
        self.baseline = baseline
        self.measure = measure
    }
}

/// The part of flexbox React Native views use in the standard components:
/// a direction, `gap`, `justifyContent`, `alignItems`, `flexWrap` and `flex`
/// on children. As in React Native, items do not shrink, `flex: n` shares
/// the free space in proportion to `n`, and lines of a wrapping layout pack
/// at the start.
public struct FlexLayout: Layout, Equatable, Sendable {
    public var axis: Axis
    public var gap: Double
    public var justify: FlexJustify
    public var align: FlexAlign
    public var wraps: Bool

    public init(axis: Axis, gap: Double = 0, justify: FlexJustify = .flexStart, align: FlexAlign = .stretch, wraps: Bool = false) {
        self.axis = axis
        self.gap = gap
        self.justify = justify
        self.align = align
        self.wraps = wraps
    }

    // MARK: Layout

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        size(for: items(subviews), proposal: proposal)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: items(subviews), in: bounds)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func items(_ subviews: Subviews) -> [FlexItem] {
        subviews.map { subview in
            FlexItem(
                flex: subview[FlexGrowKey.self],
                baseline: { proposal in subview.dimensions(in: proposal)[VerticalAlignment.firstTextBaseline] },
                measure: { subview.sizeThatFits($0) }
            )
        }
    }

    // MARK: Solver

    private struct Line {
        var indices: [Int]
        var sizes: [CGSize]
        var main: CGFloat
        var cross: CGFloat
    }

    private func main(_ size: CGSize) -> CGFloat { axis == .horizontal ? size.width : size.height }
    private func cross(_ size: CGSize) -> CGFloat { axis == .horizontal ? size.height : size.width }

    private func proposal(main: CGFloat?, cross: CGFloat?) -> ProposedViewSize {
        axis == .horizontal ? ProposedViewSize(width: main, height: cross) : ProposedViewSize(width: cross, height: main)
    }

    private func size(main: CGFloat, cross: CGFloat) -> CGSize {
        axis == .horizontal ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main)
    }

    private static func finite(_ value: CGFloat?) -> CGFloat? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Splits items into lines and sizes them for the space available.
    private func lines(for items: [FlexItem], main available: CGFloat?, cross crossAvailable: CGFloat?) -> [Line] {
        let gap = CGFloat(gap)
        let natural = items.map { $0.flex > 0 ? CGSize.zero : $0.measure(proposal(main: nil, cross: crossAvailable)) }
        var groups: [[Int]] = [[]]
        var used: CGFloat = 0
        for index in items.indices {
            let length = main(natural[index])
            if wraps, let available, !groups[groups.count - 1].isEmpty, used + gap + length > available {
                groups.append([])
                used = 0
            }
            used += (groups[groups.count - 1].isEmpty ? 0 : gap) + length
            groups[groups.count - 1].append(index)
        }
        return groups.filter { !$0.isEmpty }.map { indices in
            var sizes = indices.map { natural[$0] }
            let totalFlex = indices.reduce(0) { $0 + max(items[$1].flex, 0) }
            let fixed = zip(indices, sizes).filter { items[$0.0].flex <= 0 }.reduce(0) { $0 + main($1.1) }
            let gaps = gap * CGFloat(max(indices.count - 1, 0))
            for (position, index) in indices.enumerated() where items[index].flex > 0 {
                let share = available.map { max($0 - fixed - gaps, 0) * CGFloat(items[index].flex / totalFlex) }
                let measured = items[index].measure(proposal(main: share, cross: crossAvailable))
                sizes[position] = size(main: share ?? main(measured), cross: cross(measured))
            }
            return Line(
                indices: indices,
                sizes: sizes,
                main: sizes.reduce(0) { $0 + main($1) } + gaps,
                cross: sizes.map(cross).max() ?? 0
            )
        }
    }

    /// The layout's size for a proposal.
    public func size(for items: [FlexItem], proposal: ProposedViewSize) -> CGSize {
        let mainProposal = Self.finite(axis == .horizontal ? proposal.width : proposal.height)
        let crossProposal = Self.finite(axis == .horizontal ? proposal.height : proposal.width)
        let lines = lines(for: items, main: mainProposal, cross: crossProposal)
        let contentMain = lines.map(\.main).max() ?? 0
        let contentCross = lines.reduce(0) { $0 + $1.cross } + CGFloat(gap) * CGFloat(max(lines.count - 1, 0))
        let fillsMain = wraps || justify != .flexStart || items.contains { $0.flex > 0 }
        return size(
            main: fillsMain ? (mainProposal ?? contentMain) : contentMain,
            cross: crossProposal ?? contentCross
        )
    }

    /// Each item's frame when the layout fills `bounds`.
    public func frames(for items: [FlexItem], in bounds: CGRect) -> [CGRect] {
        let available = main(bounds.size)
        let crossAvailable = cross(bounds.size)
        let lines = lines(for: items, main: available, cross: crossAvailable)
        var frames = Array(repeating: CGRect.zero, count: items.count)
        var crossOffset: CGFloat = 0
        for line in lines {
            let lineCross = lines.count == 1 ? crossAvailable : line.cross
            let count = CGFloat(line.indices.count)
            let free = available - line.main
            var start: CGFloat = 0
            var spacing = CGFloat(gap)
            switch justify {
            case .flexStart: break
            case .flexEnd: start = free
            case .center: start = free / 2
            case .spaceBetween: if count > 1 { spacing += max(free, 0) / (count - 1) }
            case .spaceAround:
                start = max(free, 0) / count / 2
                spacing += max(free, 0) / count
            case .spaceEvenly:
                start = max(free, 0) / (count + 1)
                spacing += start
            }
            let baselines = align == .baseline
                ? zip(line.indices, line.sizes).map { items[$0.0].baseline(ProposedViewSize($0.1)) }
                : []
            let maxBaseline = baselines.compactMap { $0 }.max()
            var position = start
            for (offset, index) in line.indices.enumerated() {
                var itemSize = line.sizes[offset]
                var crossPosition: CGFloat = 0
                switch align {
                case .flexStart: break
                case .center: crossPosition = (lineCross - cross(itemSize)) / 2
                case .flexEnd: crossPosition = lineCross - cross(itemSize)
                case .stretch: itemSize = size(main: main(itemSize), cross: lineCross)
                case .baseline:
                    if let maxBaseline, let baseline = baselines[offset] { crossPosition = maxBaseline - baseline }
                }
                let origin = axis == .horizontal
                    ? CGPoint(x: bounds.minX + position, y: bounds.minY + crossOffset + crossPosition)
                    : CGPoint(x: bounds.minX + crossOffset + crossPosition, y: bounds.minY + position)
                frames[index] = CGRect(origin: origin, size: itemSize)
                position += main(itemSize) + spacing
            }
            crossOffset += lineCross + CGFloat(gap)
        }
        return frames
    }
}

/// A child's `flex` for the ``FlexLayout`` it sits in.
struct FlexGrowKey: LayoutValueKey {
    static let defaultValue: Double = 0
}

/// What a child knows about the flex layout around it.
struct FlexParent: Equatable {
    var axis: Axis
    var stretches: Bool
}

private struct FlexParentKey: EnvironmentKey {
    static let defaultValue: FlexParent? = nil
}

extension EnvironmentValues {
    var flexParent: FlexParent? {
        get { self[FlexParentKey.self] }
        set { self[FlexParentKey.self] = newValue }
    }
}

extension View {
    /// Makes a container fill what a stretching parent offers across its
    /// axis, and grow along it by `flex`, as a React Native view does.
    func flexChild(_ flex: Double?) -> some View {
        modifier(FlexChild(flex: flex ?? 0))
    }
}

private struct FlexChild: ViewModifier {
    let flex: Double
    @Environment(\.flexParent) private var parent

    func body(content: Content) -> some View {
        let grows = flex > 0
        let fillsWidth = parent.map { ($0.axis == .vertical && $0.stretches) || ($0.axis == .horizontal && grows) } ?? false
        let fillsHeight = parent.map { ($0.axis == .horizontal && $0.stretches) || ($0.axis == .vertical && grows) } ?? false
        content
            .frame(maxWidth: fillsWidth ? .infinity : nil, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .layoutValue(key: FlexGrowKey.self, value: max(flex, 0))
    }
}

/// Lays out content with a flex layout.
struct FlexStack<Content: View>: View {
    let layout: FlexLayout
    @ViewBuilder let content: Content

    var body: some View {
        layout { content }
            .environment(\.flexParent, FlexParent(axis: layout.axis, stretches: layout.align == .stretch))
    }
}
