import JSONRender
import SwiftUI
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// The feedback and composite components of the React Native standard library.

@MainActor
@Suite("Standard feedback and composite components")
struct CompositeComponentTests {
    @Test("Spinner is small and blue by default")
    func spinner() throws {
        let plain = try SpinnerComponent.Model(render("Spinner", [:]).context)
        #expect(plain.size == .small)
        #expect(plain.color == .css("#3b82f6"))
        let large = try SpinnerComponent.Model(render("Spinner", ["size": "large", "color": "#000000"]).context)
        #expect(large.size == .large)
        #expect(large.color == .css("black"))
    }

    @Test("ProgressBar clamps progress to 0...1")
    func progressBar() throws {
        let model = try ProgressBarComponent.Model(render("ProgressBar", ["progress": 0.4]).context)
        #expect(model.progress == 0.4)
        #expect(model.height == 6)
        #expect(model.color == .css("#3b82f6"))
        #expect(model.trackColor == .css("#e5e7eb"))
        #expect(try ProgressBarComponent.Model(render("ProgressBar", ["progress": 3]).context).progress == 1)
        #expect(try ProgressBarComponent.Model(render("ProgressBar", ["progress": -1]).context).progress == 0)
        #expect(try ProgressBarComponent.Model(render("ProgressBar", [:]).context).progress == 0)
        let styled = try ProgressBarComponent.Model(render("ProgressBar", ["progress": 1, "height": 10, "color": "red", "trackColor": "white"]).context)
        #expect(styled.height == 10)
        #expect(styled.color == .css("#f00"))
        #expect(styled.trackColor == .css("#fff"))
    }

    @Test("Card is elevated unless elevated is false, even when null")
    func cardElevation() throws {
        #expect(try CardComponent.Model(render("Card", [:]).context).isElevated)
        #expect(try CardComponent.Model(render("Card", ["elevated": nil]).context).isElevated)
        #expect(try !CardComponent.Model(render("Card", ["elevated": false]).context).isElevated)
    }

    @Test("Card titles and defaults")
    func card() throws {
        let model = try CardComponent.Model(render("Card", ["title": "Details", "subtitle": "More"]).context)
        #expect(model.title == "Details")
        #expect(model.subtitle == "More")
        #expect(model.titleSpacing == 2)
        #expect(model.padding == 16)
        #expect(model.backgroundColor == .css("#ffffff"))
        #expect(model.borderRadius == 12)

        let titleOnly = try CardComponent.Model(render("Card", ["title": "Details", "subtitle": "", "padding": 8, "borderRadius": 0]).context)
        #expect(titleOnly.subtitle == nil)
        #expect(titleOnly.titleSpacing == 12)
        #expect(titleOnly.padding == 8)
        #expect(titleOnly.borderRadius == 0)
    }

    @Test("ListItem is pressable only when press is bound")
    func listItem() async throws {
        let rendered = try render("ListItem", [
            "title": "Settings", "subtitle": "Preferences", "leading": "*", "trailing": "On", "showChevron": true,
        ], on: events("press"))
        let model = try ListItemComponent.Model(rendered.context)
        #expect(model.title == "Settings")
        #expect(model.subtitle == "Preferences")
        #expect(model.leading == "*")
        #expect(model.trailing == "On")
        #expect(model.showsChevron)
        #expect(model.isPressable)
        model.press()
        await rendered.runtime.settle()
        #expect(rendered.log.actions == ["press"])

        let plain = try ListItemComponent.Model(render("ListItem", ["title": "Settings"]).context)
        #expect(!plain.isPressable)
        #expect(!plain.showsChevron)
        #expect(plain.subtitle == nil)
    }

    @Test("Modal follows its visible prop and slides by default")
    func modal() throws {
        let shown = try ModalComponent.Model(render("Modal", ["visible": true, "title": "Hello"]).context)
        #expect(shown.isPresented)
        #expect(shown.title == "Hello")
        #expect(shown.animation == .slide)
        let hidden = try ModalComponent.Model(render("Modal", ["visible": false, "animationType": "fade"]).context)
        #expect(!hidden.isPresented)
        #expect(hidden.animation == .fade)
        #expect(try ModalComponent.Model(render("Modal", ["visible": true, "animationType": "none"]).context).animation == ModalComponent.Animation.none)
    }

    @Test("the standard registry has every standard component")
    func registryHasEveryComponent() {
        let names = StandardCatalog.catalog.componentNames
        #expect(names.count == 26)
        #expect(names.allSatisfy { Registry.standard.hasComponent($0) })
        #expect(Set(Registry.standard.components.keys) == Set(names))
    }

    @Test("host components replace standard ones with the same name")
    func hostComponentsReplaceStandard() {
        let custom = Component { _ in Text("custom") }
        let registry = Registry(components: ["Button": custom, "Brand": custom]).includingStandard()
        #expect(registry.hasComponent("Brand"))
        #expect(registry.hasComponent("Heading"))
        #expect(registry.components.count == 27)
    }
}
