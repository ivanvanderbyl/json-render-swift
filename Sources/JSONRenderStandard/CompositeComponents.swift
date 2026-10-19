import JSONRender
import JSONRenderUI
import SwiftUI

// The feedback and composite components of @json-render/react-native's
// standard library.

/// `Spinner`: an activity indicator, small and blue unless set.
public struct SpinnerComponent: View {
    public enum Size: String, Sendable { case small, large }

    @MainActor
    public struct Model {
        public var size: Size
        public var color: CSSColor?

        public init(_ context: ComponentContext) {
            size = context.choice("size", default: .small)
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#3b82f6")
        }
    }

    let model: Model

    public init(_ context: ComponentContext) {
        model = Model(context)
    }

    public var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(model.size == .large ? .large : .small)
            .tint(model.color?.color)
    }
}

/// `ProgressBar`: a track filled to `progress`, clamped to 0...1.
public struct ProgressBarComponent: View {
    @MainActor
    public struct Model {
        public var progress: Double
        public var height: Double
        public var color: CSSColor?
        public var trackColor: CSSColor?

        public init(_ context: ComponentContext) {
            // A missing progress is NaN upstream, which draws no fill.
            progress = context.number("progress").map { min(max($0, 0), 1) } ?? 0
            height = context.number("height") ?? 6
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#3b82f6")
            trackColor = context.string("trackColor").map(CSSColor.init) ?? CSSColor("#e5e7eb")
        }
    }

    let model: Model

    public init(_ context: ComponentContext) {
        model = Model(context)
    }

    public var body: some View {
        Track(progress: model.progress, height: model.height, color: model.color, trackColor: model.trackColor)
            .accessibilityElement()
            .accessibilityValue(Text("\(Int((model.progress * 100).rounded()))%"))
    }
}

/// `Card`: a rounded panel with an optional title and subtitle above its
/// children. It has a shadow unless `elevated` is false.
public struct CardComponent: View {
    @MainActor
    public struct Model {
        public var title: String?
        public var subtitle: String?
        /// The space below the title: 2 points when a subtitle follows, else 12.
        public var titleSpacing: Double
        public var padding: Double
        public var backgroundColor: CSSColor?
        public var borderRadius: Double
        public var isElevated: Bool

        public init(_ context: ComponentContext) throws {
            title = try context.optionalText("title")
            subtitle = try context.optionalText("subtitle")
            titleSpacing = context.truthy("subtitle") ? 2 : 12
            padding = context.number("padding") ?? 16
            backgroundColor = context.string("backgroundColor").map(CSSColor.init) ?? CSSColor("#ffffff")
            borderRadius = context.number("borderRadius") ?? 12
            // `p.elevated !== false`: null and missing both mean elevated.
            isElevated = context.props["elevated"] != .bool(false)
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
        children = context.children
    }

    public var body: some View {
        FlexStack(layout: FlexLayout(axis: .vertical)) {
            if let title = model.title {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CSSColor("#111827")!.color)
                    .padding(.bottom, model.titleSpacing)
            }
            if let subtitle = model.subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(CSSColor("#6b7280")!.color)
                    .padding(.bottom, 12)
            }
            children
        }
        .padding(model.padding)
        .background {
            RoundedRectangle(cornerRadius: model.borderRadius)
                .fill(model.backgroundColor?.color ?? .clear)
                .shadow(color: .black.opacity(model.isElevated ? 0.1 : 0), radius: 8 / 2, x: 0, y: 2)
        }
        .flexChild(nil)
    }
}

/// `ListItem`: a row with a title, optional subtitle, leading and trailing
/// text and a chevron. It is tappable, emitting `press`, only when the
/// element binds `press`.
public struct ListItemComponent: View {
    @MainActor
    public struct Model {
        let context: ComponentContext
        public var title: String
        public var subtitle: String?
        public var leading: String?
        public var trailing: String?
        public var showsChevron: Bool
        public var isPressable: Bool

        public init(_ context: ComponentContext) throws {
            self.context = context
            title = try context.text("title")
            subtitle = try context.optionalText("subtitle")
            leading = try context.optionalText("leading")
            trailing = try context.optionalText("trailing")
            showsChevron = context.truthy("showChevron")
            isPressable = context.isBound("press")
        }

        public func press() { context.emit("press") }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        if model.isPressable {
            PressArea(dimming: 0.7, pressedBackground: CSSColor("#f9fafb")!.color, onPress: { model.press() }) { content }
                .flexChild(nil)
        } else {
            content.flexChild(nil)
        }
    }

    private var content: some View {
        let grey = CSSColor("#6b7280")!.color
        return HStack(spacing: 0) {
            if let leading = model.leading {
                Text(leading).font(.system(size: 16)).foregroundStyle(grey)
                    .frame(width: 24, alignment: .center)
                    .padding(.trailing, 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.system(size: 16)).foregroundStyle(CSSColor("#111827")!.color)
                if let subtitle = model.subtitle {
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(grey)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = model.trailing {
                Text(trailing).font(.system(size: 14)).foregroundStyle(grey).padding(.leading, 8)
            }
            if model.showsChevron {
                Text(">").font(.system(size: 16)).foregroundStyle(CSSColor("#9ca3af")!.color).padding(.leading, 8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

/// `Modal`: an overlay with an optional title and its children, shown while
/// `visible` is true. Like upstream, the user cannot dismiss it; bind
/// `visible` with `$bindState` and change the state to close it.
public struct ModalComponent: View {
    public enum Animation: String, Sendable { case slide, fade, none }

    @MainActor
    public struct Model {
        public var isPresented: Bool
        public var title: String?
        public var animation: Animation

        public init(_ context: ComponentContext) throws {
            isPresented = context.truthy("visible")
            title = try context.optionalText("title")
            animation = context.choice("animationType", default: .slide)
        }
    }

    let model: Model
    let children: Children

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
        children = context.children
    }

    public var body: some View {
        let presented = Binding(get: { model.isPresented }, set: { _ in })
        Color.clear
            .frame(width: 0, height: 0)
            #if os(iOS)
            .fullScreenCover(isPresented: presented) { sheet.presentationBackground(.clear) }
            .transaction { if model.animation != .slide { $0.disablesAnimations = true } }
            #else
            .sheet(isPresented: presented) { sheet }
            #endif
    }

    private var sheet: some View {
        ModalSheet(title: model.title, fades: model.animation == .fade) { children }
            .interactiveDismissDisabled()
    }
}

/// The overlay and bottom panel of upstream's modal styles.
private struct ModalSheet<Content: View>: View {
    var title: String?
    var fades: Bool
    @ViewBuilder var content: Content
    @State private var shown = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.5).ignoresSafeArea()
                FlexStack(layout: FlexLayout(axis: .vertical)) {
                    if let title {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CSSColor("#111827")!.color)
                            .padding(.bottom, 16)
                    }
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.8, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(fades && !shown ? 0 : 1)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
    }
}
