import JSONRender
import SwiftUI
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// The input components of the React Native standard library. Inputs write
// back only through a `$bindState` or `$bindItem` binding, as upstream's
// useBoundProp does.

@MainActor
@Suite("Standard input components")
struct InputComponentTests {
    @Test("Button emits press with upstream's variant and size styles")
    func button() async throws {
        let rendered = try render("Button", ["label": "Submit"], on: events("press"))
        let model = try ButtonComponent.Model(rendered.context)
        #expect(model.label == "Submit")
        #expect(model.style == .init(background: .css("#3b82f6"), text: .css("#ffffff"), border: nil))
        #expect(model.metrics == .init(paddingHorizontal: 16, paddingVertical: 10, fontSize: 15))
        #expect(!model.isDisabled)
        model.press()
        await rendered.runtime.settle()
        #expect(rendered.log.actions == ["press"])
    }

    @Test("Button variants", arguments: [
        ("primary", "#3b82f6", "#ffffff", nil), ("secondary", "#6b7280", "#ffffff", nil),
        ("danger", "#dc2626", "#ffffff", nil), ("outline", "transparent", "#3b82f6", "#3b82f6"),
        ("ghost", "transparent", "#374151", nil), ("unknown", "#3b82f6", "#ffffff", nil),
    ] as [(String, String, String, String?)])
    func buttonVariants(variant: String, background: String, text: String, border: String?) throws {
        let model = try ButtonComponent.Model(render("Button", ["label": "x", "variant": .string(variant)]).context)
        #expect(model.style == .init(background: .css(background), text: .css(text), border: border.map(CSSColor.css)))
    }

    @Test("Button sizes", arguments: [("sm", 12.0, 6.0, 13.0), ("md", 16.0, 10.0, 15.0), ("lg", 24.0, 14.0, 17.0)])
    func buttonSizes(size: String, horizontal: Double, vertical: Double, font: Double) throws {
        let model = try ButtonComponent.Model(render("Button", ["label": "x", "size": .string(size)]).context)
        #expect(model.metrics == .init(paddingHorizontal: horizontal, paddingVertical: vertical, fontSize: font))
    }

    @Test("a disabled or loading Button does not emit")
    func disabledButton() async throws {
        for props: JSONObject in [["label": "x", "disabled": true], ["label": "x", "loading": true]] {
            let rendered = try render("Button", props, on: events("press"))
            let model = try ButtonComponent.Model(rendered.context)
            #expect(model.isDisabled)
            model.press()
            await rendered.runtime.settle()
            #expect(rendered.log.actions.isEmpty)
        }
        #expect(try ButtonComponent.Model(render("Button", ["label": "x", "loading": true]).context).isLoading)
    }

    @Test("TextInput writes typed text to its bound path")
    func textInputBinding() throws {
        let rendered = try render("TextInput", ["value": ["$bindState": "/name"], "label": "Name", "placeholder": "Your name"], state: ["name": "Ada"])
        let model = try TextInputComponent.Model(rendered.context)
        #expect(model.text == "Ada")
        #expect(model.label == "Name")
        #expect(model.placeholder == "Your name")
        #expect(model.isEditable)
        model.setText("Grace")
        #expect(rendered.runtime.get("/name") == "Grace")
    }

    @Test("an unbound TextInput shows its value and ignores typing")
    func unboundTextInput() throws {
        let rendered = try render("TextInput", ["value": "fixed"])
        let model = try TextInputComponent.Model(rendered.context)
        #expect(model.text == "fixed")
        #expect(!model.isEditable)
        model.setText("typed")
        #expect(rendered.runtime.state.isEmpty)
        #expect(try TextInputComponent.Model(render("TextInput", [:]).context).text == "")
    }

    @Test("TextInput keyboard, secure entry and multiline options")
    func textInputOptions() throws {
        let plain = try TextInputComponent.Model(render("TextInput", [:]).context)
        #expect(plain.keyboard == .default)
        #expect(!plain.isSecure)
        #expect(!plain.isMultiline)
        #expect(plain.minHeight == nil)

        let model = try TextInputComponent.Model(render("TextInput", [
            "keyboardType": "email-address", "secureTextEntry": true, "multiline": true, "numberOfLines": 4, "flex": 1,
        ]).context)
        #expect(model.keyboard == .emailAddress)
        #expect(model.isSecure)
        #expect(model.isMultiline)
        #expect(model.minHeight == 80)
        #expect(model.flex == 1)
        #expect(try TextInputComponent.Model(render("TextInput", ["multiline": true]).context).minHeight == 60)
    }

    @Test("Switch writes its bound checked path")
    func switchBinding() throws {
        let rendered = try render("Switch", ["checked": ["$bindState": "/on"], "label": "Wi-Fi"], state: ["on": false])
        let model = try SwitchComponent.Model(rendered.context)
        #expect(!model.isOn)
        #expect(model.label == "Wi-Fi")
        #expect(model.canToggle)
        model.setOn(true)
        #expect(rendered.runtime.get("/on") == true)

        let unbound = try render("Switch", ["checked": true, "disabled": true])
        let fixed = try SwitchComponent.Model(unbound.context)
        #expect(fixed.isOn)
        #expect(fixed.isDisabled)
        #expect(!fixed.canToggle)
        fixed.setOn(false)
        #expect(unbound.runtime.state.isEmpty)
    }

    @Test("Checkbox toggles its bound path unless disabled")
    func checkbox() throws {
        let rendered = try render("Checkbox", ["checked": ["$bindState": "/agree"], "label": "I agree"], state: ["agree": false])
        let model = try CheckboxComponent.Model(rendered.context)
        #expect(!model.isChecked)
        model.toggle()
        #expect(rendered.runtime.get("/agree") == true)

        let disabled = try render("Checkbox", ["checked": ["$bindState": "/agree"], "disabled": true], state: ["agree": false])
        try CheckboxComponent.Model(disabled.context).toggle()
        #expect(disabled.runtime.get("/agree") == false)

        let unbound = try render("Checkbox", ["checked": true])
        try CheckboxComponent.Model(unbound.context).toggle()
        #expect(unbound.runtime.state.isEmpty)
    }

    @Test("Slider shows its value as a filled track, like upstream's display-only slider")
    func slider() throws {
        let model = try SliderComponent.Model(render("Slider", ["min": 0, "max": 200, "value": 50, "label": "Volume"]).context)
        #expect(model.progress == 0.25)
        #expect(model.valueText == "50")
        #expect(model.label == "Volume")
        #expect(model.color == .css("#3b82f6"))

        let defaults = try SliderComponent.Model(render("Slider", [:]).context)
        #expect(defaults.progress == 0)
        #expect(defaults.valueText == "0")
        #expect(try SliderComponent.Model(render("Slider", ["value": 150]).context).progress == 1)
        #expect(try SliderComponent.Model(render("Slider", ["min": 5, "max": 5, "value": 5]).context).progress == 0)
        #expect(try SliderComponent.Model(render("Slider", ["value": 0.5, "max": 1]).context).valueText == "0.5")
    }

    @Test("SearchBar emits submit with a default placeholder")
    func searchBar() async throws {
        let rendered = try render("SearchBar", ["value": "shoes"], on: events("submit"))
        let model = try SearchBarComponent.Model(rendered.context)
        #expect(model.placeholder == "Search...")
        #expect(model.value == "shoes")
        model.submit()
        await rendered.runtime.settle()
        #expect(rendered.log.actions == ["submit"])
        #expect(try SearchBarComponent.Model(render("SearchBar", ["placeholder": "Find"]).context).value == nil)
    }
}
