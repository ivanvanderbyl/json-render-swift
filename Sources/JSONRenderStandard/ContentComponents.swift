import JSONRender
import JSONRenderUI
import SwiftUI

// The content components of @json-render/react-native's standard library.

/// Horizontal text alignment, like React Native `textAlign`.
public enum TextAlign: String, Sendable {
    case left, center, right

    var alignment: Alignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}

/// Text drawn with a React Native text style.
struct StyledText: View {
    var text: String
    var size: Double
    var weight: Font.Weight = .regular
    var color: CSSColor?
    var align: TextAlign = .left
    var lineHeight: Double?
    var lineLimit: Int?

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .lineSpacing(lineHeight.map { max($0 - size * 1.2, 0) } ?? 0)
            .lineLimit(lineLimit)
            .foregroundStyle(color?.color ?? .primary)
            .multilineTextAlignment(align.textAlignment)
            .frame(maxWidth: align == .left ? nil : .infinity, alignment: align.alignment)
    }
}

/// `Heading`: bold text sized by `level`, h2 unless set.
public struct HeadingComponent: View {
    @MainActor
    public struct Model {
        public var text: String
        public var fontSize: Double
        public var weight: Font.Weight
        public var color: CSSColor?
        public var align: TextAlign

        static let sizes: [String: Double] = ["h1": 32, "h2": 24, "h3": 20, "h4": 16]

        public init(_ context: ComponentContext) throws {
            text = try context.text("text")
            // An unknown level leaves React Native's default 14 point size.
            fontSize = context.option("level", default: "h2", in: Self.sizes) ?? 14
            weight = .bold
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#111827")
            align = context.choice("align", default: .left)
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        StyledText(text: model.text, size: model.fontSize, weight: model.weight, color: model.color, align: model.align)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `Paragraph`: body text, 16 points with a 1.5 line height unless set.
public struct ParagraphComponent: View {
    @MainActor
    public struct Model {
        public var text: String
        public var fontSize: Double
        public var lineHeight: Double
        public var color: CSSColor?
        public var align: TextAlign
        public var lineLimit: Int?

        public init(_ context: ComponentContext) throws {
            text = try context.text("text")
            fontSize = context.number("fontSize") ?? 16
            lineHeight = fontSize * 1.5
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#374151")
            align = context.choice("align", default: .left)
            // React Native treats numberOfLines 0 as no limit.
            lineLimit = context.number("numberOfLines").flatMap { $0 >= 1 ? Int($0) : nil }
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        StyledText(
            text: model.text, size: model.fontSize, color: model.color, align: model.align,
            lineHeight: model.lineHeight, lineLimit: model.lineLimit
        )
    }
}

/// `Label`: small utility text, `sm` unless set, semibold when `bold`.
public struct LabelComponent: View {
    @MainActor
    public struct Model {
        public var text: String
        public var fontSize: Double
        public var weight: Font.Weight
        public var color: CSSColor?

        static let sizes: [String: Double] = ["xs": 10, "sm": 12, "md": 14]

        public init(_ context: ComponentContext) throws {
            text = try context.text("text")
            fontSize = context.option("size", default: "sm", in: Self.sizes) ?? 14
            weight = context.truthy("bold") ? .semibold : .regular
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#6b7280")
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        StyledText(text: model.text, size: model.fontSize, weight: model.weight, color: model.color)
    }
}

/// How an image fills its frame, like React Native `resizeMode`.
public enum ResizeMode: String, Sendable {
    case cover, contain, stretch, center
}

/// `Image`: a remote image, full width and 200 points high unless sized.
public struct ImageComponent: View {
    @MainActor
    public struct Model {
        public var url: URL?
        public var accessibilityLabel: String?
        public var resizeMode: ResizeMode
        /// Nil fills the available width, like upstream's "100%".
        public var width: Double?
        public var height: Double
        public var borderRadius: Double

        public init(_ context: ComponentContext) {
            url = context.string("src").flatMap(URL.init(string:))
            accessibilityLabel = context.string("alt")
            resizeMode = context.choice("resizeMode", default: .cover)
            width = context.number("width")
            height = context.number("height") ?? 200
            borderRadius = context.number("borderRadius") ?? 0
        }
    }

    let model: Model

    public init(_ context: ComponentContext) {
        model = Model(context)
    }

    public var body: some View {
        AsyncImage(url: model.url) { image in
            switch model.resizeMode {
            case .cover: image.resizable().scaledToFill()
            case .contain: image.resizable().scaledToFit()
            case .stretch: image.resizable()
            case .center: ViewThatFits { image; image.resizable().scaledToFit() }
            }
        } placeholder: {
            Color.clear
        }
        .frame(width: model.width.map { CGFloat($0) }, height: model.height)
        .frame(maxWidth: model.width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: model.borderRadius))
        .accessibilityLabel(model.accessibilityLabel.map { Text($0) } ?? Text(""))
    }
}

/// `Avatar`: a circle with an image, or initials on a coloured background.
public struct AvatarComponent: View {
    @MainActor
    public struct Model {
        public var size: Double?
        public var imageURL: URL?
        public var initials: String
        public var backgroundColor: CSSColor?
        public var fontSize: Double?

        static let sizes: [String: Double] = ["sm": 32, "md": 48, "lg": 64, "xl": 96]

        public init(_ context: ComponentContext) throws {
            size = context.option("size", default: "md", in: Self.sizes)
            fontSize = size.map { $0 * 0.4 }
            if context.truthy("src") {
                imageURL = context.string("src").flatMap(URL.init(string:))
                backgroundColor = CSSColor("#e5e7eb")
            } else {
                imageURL = nil
                backgroundColor = context.string("backgroundColor").map(CSSColor.init) ?? CSSColor("#6366f1")
            }
            let initials = context.props["initials"] ?? .undefined
            self.initials = initials.isNullish ? "?" : try ReactText.string(initials)
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        let size = model.size.map { CGFloat($0) }
        ZStack {
            Circle().fill(model.backgroundColor?.color ?? .clear)
            if let url = model.imageURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                    .clipShape(Circle())
            } else {
                Text(model.initials)
                    .font(.system(size: model.fontSize ?? 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// `Badge`: a small pill with a label, coloured by `variant`.
public struct BadgeComponent: View {
    @MainActor
    public struct Model {
        public var label: String
        public var backgroundColor: CSSColor?
        public var textColor: CSSColor?

        static let variants: [String: (String, String)] = [
            "default": ("#e5e7eb", "#374151"),
            "info": ("#dbeafe", "#1d4ed8"),
            "success": ("#dcfce7", "#15803d"),
            "warning": ("#fef3c7", "#92400e"),
            "error": ("#fee2e2", "#dc2626"),
        ]

        public init(_ context: ComponentContext) throws {
            label = try context.text("label")
            let colors = context.option("variant", default: "default", in: Self.variants) ?? ("#e5e7eb", "#374151")
            backgroundColor = CSSColor(colors.0)
            textColor = CSSColor(colors.1)
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        Text(model.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(model.textColor?.color ?? .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(model.backgroundColor?.color ?? .clear, in: Capsule())
    }
}

/// `Chip`: a tag that emits `press`, with a remove button that emits
/// `remove` when the element binds it.
public struct ChipComponent: View {
    @MainActor
    public struct Model {
        let context: ComponentContext
        public var label: String
        public var backgroundColor: CSSColor?
        public var textColor: CSSColor?
        public var showsRemove: Bool

        public init(_ context: ComponentContext) throws {
            self.context = context
            label = try context.text("label")
            if context.truthy("selected") {
                backgroundColor = CSSColor("#6366f1")
                textColor = CSSColor("#ffffff")
            } else {
                backgroundColor = context.string("backgroundColor").map(CSSColor.init) ?? CSSColor("#f3f4f6")
                textColor = CSSColor("#374151")
            }
            showsRemove = context.isBound("remove")
        }

        public func press() { context.emit("press") }
        public func remove() { context.emit("remove") }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        let textColor = model.textColor?.color ?? .primary
        HStack(spacing: 4) {
            Text(model.label).font(.system(size: 14)).foregroundStyle(textColor)
            if model.showsRemove {
                Button(action: { model.remove() }) {
                    Text("x").font(.system(size: 14, weight: .bold)).foregroundStyle(textColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(model.backgroundColor?.color ?? .clear, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { model.press() }
    }
}
