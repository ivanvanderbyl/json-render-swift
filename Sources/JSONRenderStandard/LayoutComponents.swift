import JSONRender
import JSONRenderUI
import SwiftUI

// The layout components of @json-render/react-native's standard library
// (packages/react-native/src/components/standard.tsx). Each view draws a
// Model that applies the props and defaults the upstream component applies.

/// `Container`: a generic wrapper with padding, margin, background colour,
/// corner radius and flex. Children stack vertically and stretch, like a
/// React Native `View`.
public struct ContainerComponent: View {
    @MainActor
    public struct Model {
        public var padding: EdgeInsets
        public var margin: Double
        public var backgroundColor: CSSColor?
        public var borderRadius: Double?
        public var flex: Double?

        public init(_ context: ComponentContext) {
            let all = context.number("padding")
            let horizontal = context.number("paddingHorizontal") ?? all ?? 0
            let vertical = context.number("paddingVertical") ?? all ?? 0
            padding = EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
            margin = context.number("margin") ?? 0
            backgroundColor = context.color("backgroundColor")
            borderRadius = context.number("borderRadius")
            flex = context.number("flex")
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) {
        model = Model(context)
        children = context.children
    }

    public var body: some View {
        FlexStack(layout: FlexLayout(axis: .vertical)) { children }
            .padding(model.padding)
            .background(model.backgroundColor?.color ?? .clear, in: RoundedRectangle(cornerRadius: model.borderRadius ?? 0))
            .padding(model.margin)
            .flexChild(model.flex)
    }
}

/// `Row`: children side by side, with gap, alignment, justification and wrap.
public struct RowComponent: View {
    @MainActor
    public struct Model {
        public var layout: FlexLayout
        public var padding: Double
        public var flex: Double?

        public init(_ context: ComponentContext) {
            layout = FlexLayout(
                axis: .horizontal,
                gap: context.number("gap") ?? 0,
                justify: context.choice("justifyContent", default: .flexStart),
                align: context.choice("alignItems", default: .stretch),
                wraps: context.string("flexWrap") == "wrap"
            )
            padding = context.number("padding") ?? 0
            flex = context.number("flex")
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) {
        model = Model(context)
        children = context.children
    }

    public var body: some View {
        FlexStack(layout: model.layout) { children }
            .padding(model.padding)
            .flexChild(model.flex)
    }
}

/// `Column`: children stacked top to bottom, with gap, alignment and
/// justification.
public struct ColumnComponent: View {
    @MainActor
    public struct Model {
        public var layout: FlexLayout
        public var padding: Double
        public var flex: Double?

        public init(_ context: ComponentContext) {
            layout = FlexLayout(
                axis: .vertical,
                gap: context.number("gap") ?? 0,
                justify: context.choice("justifyContent", default: .flexStart),
                align: context.choice("alignItems", default: .stretch)
            )
            padding = context.number("padding") ?? 0
            flex = context.number("flex")
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) {
        model = Model(context)
        children = context.children
    }

    public var body: some View {
        FlexStack(layout: model.layout) { children }
            .padding(model.padding)
            .flexChild(model.flex)
    }
}

/// `ScrollContainer`: scrollable content, vertical unless `horizontal`. It
/// fills its parent unless `flex` says otherwise, as upstream's
/// `flex: p.flex ?? 1` does.
public struct ScrollContainerComponent: View {
    @MainActor
    public struct Model {
        public var axis: Axis
        public var showsIndicators: Bool
        public var padding: Double
        public var backgroundColor: CSSColor?
        public var flex: Double

        public init(_ context: ComponentContext) {
            axis = context.flag("horizontal", default: false) ? .horizontal : .vertical
            showsIndicators = context.flag("showsScrollIndicator", default: true)
            padding = context.number("padding") ?? 0
            backgroundColor = context.color("backgroundColor")
            flex = context.number("flex") ?? 1
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) {
        model = Model(context)
        children = context.children
    }

    public var body: some View {
        ScrollView(model.axis == .horizontal ? .horizontal : .vertical, showsIndicators: model.showsIndicators) {
            FlexStack(layout: FlexLayout(axis: model.axis)) { children }
                .padding(model.padding)
        }
        .background(model.backgroundColor?.color ?? .clear)
        .flexChild(model.flex)
    }
}

/// `SafeArea`: fills the screen inside the safe area, with the background
/// colour behind the system bars.
public struct SafeAreaComponent: View {
    @MainActor
    public struct Model {
        public var backgroundColor: CSSColor?

        public init(_ context: ComponentContext) {
            backgroundColor = context.color("backgroundColor")
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) {
        model = Model(context)
        children = context.children
    }

    public var body: some View {
        FlexStack(layout: FlexLayout(axis: .vertical)) { children }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background((model.backgroundColor?.color ?? .clear).ignoresSafeArea())
            .flexChild(1)
    }
}

/// `Spacer`: empty space, a square of `size` points or flexible by `flex`.
public struct SpacerComponent: View {
    @MainActor
    public struct Model {
        public var size: Double?
        public var flex: Double?

        public init(_ context: ComponentContext) {
            size = context.number("size")
            flex = context.number("flex")
        }
    }

    let model: Model

    public init(_ context: ComponentContext) {
        model = Model(context)
    }

    public var body: some View {
        Color.clear
            .frame(width: model.size.map { CGFloat($0) }, height: model.size.map { CGFloat($0) })
            .frame(minWidth: 0, minHeight: 0)
            .flexChild(model.flex)
    }
}

/// `Pressable`: makes its children tappable. A tap emits `press` and a long
/// press emits `longPress`; the content dims while pressed.
public struct PressableComponent: View {
    @MainActor
    public struct Model {
        let context: ComponentContext

        public init(_ context: ComponentContext) {
            self.context = context
        }

        public func press() { context.emit("press") }
        public func longPress() { context.emit("longPress") }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) {
        model = Model(context)
        children = context.children
    }

    public var body: some View {
        PressArea(dimming: 0.7, onPress: { model.press() }, onLongPress: { model.longPress() }) {
            FlexStack(layout: FlexLayout(axis: .vertical)) { children }
        }
        .flexChild(nil)
    }
}

/// `Divider`: a thin line, horizontal unless `direction` is "vertical".
public struct DividerComponent: View {
    @MainActor
    public struct Model {
        public var isVertical: Bool
        public var thickness: Double
        public var color: CSSColor?
        public var margin: Double

        public init(_ context: ComponentContext) {
            isVertical = context.string("direction") == "vertical"
            thickness = context.number("thickness") ?? 1
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#e5e7eb")
            margin = context.number("margin") ?? 8
        }
    }

    let model: Model

    public init(_ context: ComponentContext) {
        model = Model(context)
    }

    public var body: some View {
        let line = Rectangle().fill(model.color?.color ?? .clear)
        if model.isVertical {
            line.frame(width: model.thickness).frame(maxHeight: .infinity).padding(.horizontal, model.margin)
        } else {
            line.frame(height: model.thickness).frame(maxWidth: .infinity).padding(.vertical, model.margin)
        }
    }
}

/// A tappable area that dims while pressed, like a React Native `Pressable`.
/// With `onLongPress`, holding for half a second runs it instead of
/// `onPress`, as React Native does when a pressable has `onLongPress`.
struct PressArea<Content: View>: View {
    var dimming: Double
    var pressedBackground: Color?
    var isEnabled = true
    var onPress: () -> Void
    var onLongPress: (() -> Void)?
    @ViewBuilder var content: Content

    init(dimming: Double, pressedBackground: Color? = nil, isEnabled: Bool = true, onPress: @escaping () -> Void, onLongPress: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.dimming = dimming
        self.pressedBackground = pressedBackground
        self.isEnabled = isEnabled
        self.onPress = onPress
        self.onLongPress = onLongPress
        self.content = content()
    }

    @State private var pressed = false

    var body: some View {
        if let onLongPress {
            content
                .contentShape(Rectangle())
                .opacity(pressed ? dimming : 1)
                .background(pressed ? pressedBackground : nil)
                .onTapGesture { if isEnabled { onPress() } }
                .onLongPressGesture(minimumDuration: 0.5) {
                    if isEnabled { onLongPress() }
                } onPressingChanged: { pressing in
                    pressed = pressing && isEnabled
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if isEnabled { onPress() } }
                .accessibilityAction(named: Text("Long press")) { if isEnabled { onLongPress() } }
        } else {
            Button(action: onPress) { content.contentShape(Rectangle()) }
                .buttonStyle(PressStyle(dimming: dimming, pressedBackground: pressedBackground))
                .disabled(!isEnabled)
        }
    }
}

struct PressStyle: ButtonStyle {
    var dimming: Double
    var pressedBackground: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? dimming : 1)
            .background(configuration.isPressed ? pressedBackground : nil)
    }
}
