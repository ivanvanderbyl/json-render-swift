import JSONRender
import JSONRenderUI
import SwiftUI

// The input components of @json-render/react-native's standard library.
// Like upstream, inputs write only through a bound prop (`$bindState` or
// `$bindItem`); an unbound input shows its value and ignores edits.

/// `Button`: a labelled button that emits `press`, styled by `variant` and
/// `size`. It is disabled while `disabled` or `loading`.
public struct ButtonComponent: View {
    public struct Style: Equatable {
        public var background: CSSColor?
        public var text: CSSColor?
        public var border: CSSColor?

        public init(background: CSSColor?, text: CSSColor?, border: CSSColor?) {
            self.background = background
            self.text = text
            self.border = border
        }
    }

    public struct Metrics: Equatable {
        public var paddingHorizontal: Double
        public var paddingVertical: Double
        public var fontSize: Double

        public init(paddingHorizontal: Double, paddingVertical: Double, fontSize: Double) {
            self.paddingHorizontal = paddingHorizontal
            self.paddingVertical = paddingVertical
            self.fontSize = fontSize
        }
    }

    @MainActor
    public struct Model {
        let context: ComponentContext
        public var label: String
        public var style: Style
        public var metrics: Metrics
        public var isDisabled: Bool
        public var isLoading: Bool

        static let variants: [String: Style] = [
            "primary": Style(background: CSSColor("#3b82f6"), text: CSSColor("#ffffff"), border: nil),
            "secondary": Style(background: CSSColor("#6b7280"), text: CSSColor("#ffffff"), border: nil),
            "danger": Style(background: CSSColor("#dc2626"), text: CSSColor("#ffffff"), border: nil),
            "outline": Style(background: CSSColor("transparent"), text: CSSColor("#3b82f6"), border: CSSColor("#3b82f6")),
            "ghost": Style(background: CSSColor("transparent"), text: CSSColor("#374151"), border: nil),
        ]

        static let sizes: [String: Metrics] = [
            "sm": Metrics(paddingHorizontal: 12, paddingVertical: 6, fontSize: 13),
            "md": Metrics(paddingHorizontal: 16, paddingVertical: 10, fontSize: 15),
            "lg": Metrics(paddingHorizontal: 24, paddingVertical: 14, fontSize: 17),
        ]

        public init(_ context: ComponentContext) throws {
            self.context = context
            label = try context.text("label")
            style = context.option("variant", default: "primary", in: Self.variants) ?? Self.variants["primary"]!
            metrics = context.option("size", default: "md", in: Self.sizes) ?? Self.sizes["md"]!
            isLoading = context.truthy("loading")
            isDisabled = context.truthy("disabled") || isLoading
        }

        public func press() {
            guard !isDisabled else { return }
            context.emit("press")
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        let textColor = model.style.text?.color ?? .primary
        Button(action: { model.press() }) {
            HStack(spacing: 0) {
                if model.isLoading {
                    ProgressView().controlSize(.small).tint(textColor).padding(.trailing, 8)
                }
                Text(model.label)
                    .font(.system(size: model.metrics.fontSize, weight: .semibold))
                    .foregroundStyle(textColor)
            }
            .padding(.horizontal, model.metrics.paddingHorizontal)
            .padding(.vertical, model.metrics.paddingVertical)
            .background(model.style.background?.color ?? .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if let border = model.style.border {
                    RoundedRectangle(cornerRadius: 8).stroke(border.color, lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressStyle(dimming: 0.8))
        .disabled(model.isDisabled)
        .opacity(model.isDisabled ? 0.5 : 1)
    }
}

/// The keyboard a `TextInput` asks for, like React Native `keyboardType`.
public enum KeyboardKind: String, Sendable {
    case `default`
    case emailAddress = "email-address"
    case numeric
    case phonePad = "phone-pad"
    case url
}

/// `TextInput`: a text field with an optional label. Typing writes the
/// bound `value` path.
public struct TextInputComponent: View {
    @MainActor
    public struct Model {
        let value: Binding<JSONValue>
        public var text: String
        public var isEditable: Bool
        public var label: String?
        public var placeholder: String?
        public var isSecure: Bool
        public var keyboard: KeyboardKind
        public var isMultiline: Bool
        public var lineCount: Int?
        /// The minimum height of a multiline field: 20 points per line.
        public var minHeight: Double?
        public var flex: Double?

        public init(_ context: ComponentContext) throws {
            value = context.binding("value")
            let current = value.wrappedValue
            text = current.isNullish ? "" : try ReactText.string(current)
            isEditable = context.bindings?["value"] != nil
            label = try context.optionalText("label")
            placeholder = context.string("placeholder")
            isSecure = context.flag("secureTextEntry", default: false)
            keyboard = context.choice("keyboardType", default: .default)
            isMultiline = context.flag("multiline", default: false)
            lineCount = context.number("numberOfLines").map { Int($0) }
            minHeight = isMultiline ? Double(lineCount ?? 3) * 20 : nil
            flex = context.number("flex")
        }

        public func setText(_ newText: String) {
            guard isEditable else { return }
            value.wrappedValue = .string(newText)
        }
    }

    let model: Model
    @State private var editing = ""

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = model.label {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CSSColor("#374151")!.color)
                    .padding(.bottom, 4)
            }
            field
                .font(.system(size: 16))
                .foregroundStyle(CSSColor("#111827")!.color)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: model.minHeight.map { CGFloat($0) }, alignment: .topLeading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CSSColor("#d1d5db")!.color, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .keyboard(model.keyboard)
        }
        .onChange(of: model.text, initial: true) { editing = model.text }
        .onChange(of: editing) {
            guard editing != model.text else { return }
            if model.isEditable { model.setText(editing) } else { editing = model.text }
        }
        .flexChild(model.flex)
    }

    @ViewBuilder private var field: some View {
        let placeholder = model.placeholder ?? ""
        if model.isSecure {
            SecureField(placeholder, text: $editing)
        } else if model.isMultiline {
            TextField(placeholder, text: $editing, axis: .vertical)
                .lineLimit(model.lineCount.map { $0...max($0, 1) } ?? 1...Int.max)
        } else {
            TextField(placeholder, text: $editing)
        }
    }
}

extension View {
    @ViewBuilder func keyboard(_ kind: KeyboardKind) -> some View {
        #if os(iOS)
        switch kind {
        case .default: keyboardType(.default)
        case .emailAddress: keyboardType(.emailAddress).textInputAutocapitalization(.never)
        case .numeric: keyboardType(.decimalPad)
        case .phonePad: keyboardType(.phonePad)
        case .url: keyboardType(.URL).textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }
}

/// `Switch`: a toggle with an optional label. Toggling writes the bound
/// `checked` path.
public struct SwitchComponent: View {
    @MainActor
    public struct Model {
        let checked: Binding<JSONValue>
        public var isOn: Bool
        public var label: String?
        public var isDisabled: Bool
        public var canToggle: Bool

        public init(_ context: ComponentContext) throws {
            checked = context.binding("checked")
            isOn = checked.wrappedValue.isTruthy
            label = try context.optionalText("label")
            isDisabled = context.flag("disabled", default: false)
            canToggle = context.bindings?["checked"] != nil
        }

        public func setOn(_ on: Bool) {
            guard canToggle else { return }
            checked.wrappedValue = .bool(on)
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { model.isOn }, set: { model.setOn($0) }))
                .labelsHidden()
                .disabled(model.isDisabled)
            if let label = model.label {
                Text(label).font(.system(size: 16)).foregroundStyle(CSSColor("#374151")!.color)
            }
        }
    }
}

/// `Checkbox`: a box with a tick and an optional label. Tapping toggles the
/// bound `checked` path unless `disabled`.
public struct CheckboxComponent: View {
    @MainActor
    public struct Model {
        let checked: Binding<JSONValue>
        public var isChecked: Bool
        public var label: String?
        public var isDisabled: Bool

        public init(_ context: ComponentContext) throws {
            checked = context.binding("checked")
            isChecked = checked.wrappedValue.isTruthy
            label = try context.optionalText("label")
            isDisabled = context.flag("disabled", default: false)
            canToggle = context.bindings?["checked"] != nil
        }

        let canToggle: Bool

        public func toggle() {
            guard !isDisabled, canToggle else { return }
            checked.wrappedValue = .bool(!isChecked)
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        let blue = CSSColor("#3b82f6")!.color
        Button(action: { model.toggle() }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(model.isChecked ? blue : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(model.isChecked ? blue : CSSColor("#d1d5db")!.color, lineWidth: 2))
                    .overlay {
                        if model.isChecked {
                            Text("\u{2713}").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 20, height: 20)
                if let label = model.label {
                    Text(label).font(.system(size: 16)).foregroundStyle(CSSColor("#374151")!.color)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isDisabled)
        .opacity(model.isDisabled ? 0.5 : 1)
        .accessibilityAddTraits(model.isChecked ? .isSelected : [])
    }
}

/// `Slider`: shows `value` between `min` and `max` as a filled track with
/// an optional label. Like upstream, it displays the value but does not
/// change it, and `step` has no effect.
public struct SliderComponent: View {
    @MainActor
    public struct Model {
        public var progress: Double
        public var valueText: String
        public var label: String?
        public var color: CSSColor?

        public init(_ context: ComponentContext) throws {
            let min = context.number("min") ?? 0
            let max = context.number("max") ?? 100
            let value = context.number("value") ?? min
            progress = Swift.min(Swift.max(max > min ? (value - min) / (max - min) : 0, 0), 1)
            valueText = JSONValue.number(value).javaScriptString
            label = try context.optionalText("label")
            color = context.string("color").map(CSSColor.init) ?? CSSColor("#3b82f6")
        }
    }

    let model: Model

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = model.label {
                HStack {
                    Text(label).font(.system(size: 14)).foregroundStyle(CSSColor("#374151")!.color)
                    Spacer()
                    Text(model.valueText).font(.system(size: 14)).foregroundStyle(CSSColor("#6b7280")!.color)
                }
            }
            Track(progress: model.progress, height: 6, color: model.color, trackColor: CSSColor("#e5e7eb"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(model.valueText))
    }
}

/// `SearchBar`: a search field that emits `submit`. A `value` prop fixes the
/// text; without one the field keeps what the user types.
public struct SearchBarComponent: View {
    @MainActor
    public struct Model {
        let context: ComponentContext
        public var placeholder: String
        public var value: String?

        public init(_ context: ComponentContext) throws {
            self.context = context
            placeholder = context.string("placeholder") ?? "Search..."
            let value = context.props["value"] ?? .undefined
            self.value = value.isNullish ? nil : try ReactText.string(value)
        }

        public func submit() { context.emit("submit") }
    }

    let model: Model
    @State private var typed = ""

    public init(_ context: ComponentContext) throws {
        model = try Model(context)
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text("Search").font(.system(size: 16)).foregroundStyle(CSSColor("#9ca3af")!.color).padding(.trailing, 8)
            TextField(model.placeholder, text: Binding(
                get: { model.value ?? typed },
                set: { if model.value == nil { typed = $0 } }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .foregroundStyle(CSSColor("#111827")!.color)
            .padding(.vertical, 10)
            .submitLabel(.search)
            .onSubmit { model.submit() }
        }
        .padding(.horizontal, 12)
        .background(CSSColor("#f3f4f6")!.color, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A rounded track filled to a fraction.
struct Track: View {
    var progress: Double
    var height: Double
    var color: CSSColor?
    var trackColor: CSSColor?

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(trackColor?.color ?? .clear)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(color?.color ?? .clear)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}
