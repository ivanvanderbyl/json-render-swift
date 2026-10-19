import JSONRender
import SwiftUI
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// The content components of the React Native standard library.

@MainActor
@Suite("Standard content components")
struct ContentComponentTests {
    @Test("Heading sizes by level, defaulting to h2", arguments: [
        ("h1", 32.0), ("h2", 24.0), ("h3", 20.0), ("h4", 16.0),
    ])
    func headingLevels(level: String, size: Double) throws {
        let model = try HeadingComponent.Model(render("Heading", ["text": "Hi", "level": .string(level)]).context)
        #expect(model.text == "Hi")
        #expect(model.fontSize == size)
    }

    @Test("Heading defaults: h2, bold, dark grey, left aligned")
    func headingDefaults() throws {
        let model = try HeadingComponent.Model(render("Heading", ["text": "Hi"]).context)
        #expect(model.fontSize == 24)
        #expect(model.weight == .bold)
        #expect(model.color == .css("#111827"))
        #expect(model.align == .left)

        let styled = try HeadingComponent.Model(render("Heading", ["text": 42, "color": "#ff0000", "align": "center"]).context)
        #expect(styled.text == "42")
        #expect(styled.color == .css("red"))
        #expect(styled.align == .center)
    }

    @Test("an object as text fails like a React child")
    func objectTextFails() throws {
        #expect(throws: (any Error).self) {
            try HeadingComponent.Model(render("Heading", ["text": ["a": 1]]).context)
        }
    }

    @Test("Paragraph is 16 point body text with a 1.5 line height")
    func paragraph() throws {
        let model = try ParagraphComponent.Model(render("Paragraph", ["text": "Body"]).context)
        #expect(model.text == "Body")
        #expect(model.fontSize == 16)
        #expect(model.lineHeight == 24)
        #expect(model.color == .css("#374151"))
        #expect(model.align == .left)
        #expect(model.lineLimit == nil)

        let styled = try ParagraphComponent.Model(render("Paragraph", [
            "text": "Body", "fontSize": 20, "numberOfLines": 2, "align": "right", "color": "#000000",
        ]).context)
        #expect(styled.fontSize == 20)
        #expect(styled.lineHeight == 30)
        #expect(styled.lineLimit == 2)
        #expect(styled.align == .right)
    }

    @Test("Label sizes and weight", arguments: [("xs", 10.0), ("sm", 12.0), ("md", 14.0)])
    func labelSizes(size: String, points: Double) throws {
        #expect(try LabelComponent.Model(render("Label", ["text": "x", "size": .string(size)]).context).fontSize == points)
    }

    @Test("Label defaults to small, regular, grey; bold is semibold")
    func labelDefaults() throws {
        let model = try LabelComponent.Model(render("Label", ["text": "Status"]).context)
        #expect(model.fontSize == 12)
        #expect(model.weight == .regular)
        #expect(model.color == .css("#6b7280"))
        #expect(try LabelComponent.Model(render("Label", ["text": "x", "bold": true]).context).weight == .semibold)
    }

    @Test("Image loads its source with upstream's size and resize defaults")
    func image() throws {
        let model = try ImageComponent.Model(render("Image", ["src": "https://example.com/a.png", "alt": "A photo"]).context)
        #expect(model.url == URL(string: "https://example.com/a.png"))
        #expect(model.accessibilityLabel == "A photo")
        #expect(model.resizeMode == .cover)
        #expect(model.width == nil)
        #expect(model.height == 200)
        #expect(model.borderRadius == 0)

        let sized = try ImageComponent.Model(render("Image", [
            "src": "https://example.com/a.png", "width": 300, "height": 150, "resizeMode": "contain", "borderRadius": 8,
        ]).context)
        #expect(sized.width == 300)
        #expect(sized.height == 150)
        #expect(sized.resizeMode == .contain)
        #expect(sized.borderRadius == 8)
    }

    @Test("Avatar shows initials on a coloured circle, or the image", arguments: [
        ("sm", 32.0), ("md", 48.0), ("lg", 64.0), ("xl", 96.0),
    ])
    func avatarSizes(size: String, points: Double) throws {
        let model = try AvatarComponent.Model(render("Avatar", ["initials": "JD", "size": .string(size)]).context)
        #expect(model.size == points)
        #expect(model.fontSize == points * 0.4)
    }

    @Test("Avatar defaults: medium, indigo, question mark")
    func avatarDefaults() throws {
        let model = try AvatarComponent.Model(render("Avatar", [:]).context)
        #expect(model.size == 48)
        #expect(model.initials == "?")
        #expect(model.backgroundColor == .css("#6366f1"))
        #expect(model.imageURL == nil)

        let photo = try AvatarComponent.Model(render("Avatar", ["src": "https://example.com/me.png", "initials": "ME"]).context)
        #expect(photo.imageURL == URL(string: "https://example.com/me.png"))
        #expect(photo.backgroundColor == .css("#e5e7eb"))
    }

    @Test("Badge colours by variant", arguments: [
        ("default", "#e5e7eb", "#374151"), ("info", "#dbeafe", "#1d4ed8"), ("success", "#dcfce7", "#15803d"),
        ("warning", "#fef3c7", "#92400e"), ("error", "#fee2e2", "#dc2626"), ("unknown", "#e5e7eb", "#374151"),
    ])
    func badge(variant: String, background: String, text: String) throws {
        let model = try BadgeComponent.Model(render("Badge", ["label": "New", "variant": .string(variant)]).context)
        #expect(model.label == "New")
        #expect(model.backgroundColor == .css(background))
        #expect(model.textColor == .css(text))
    }

    @Test("Chip emits press, and remove only when bound")
    func chip() async throws {
        let rendered = try render("Chip", ["label": "Tag"], on: events("press", "remove"))
        let model = try ChipComponent.Model(rendered.context)
        #expect(model.showsRemove)
        model.press()
        model.remove()
        await rendered.runtime.settle()
        #expect(rendered.log.actions == ["press", "remove"])

        #expect(try !ChipComponent.Model(render("Chip", ["label": "Tag"], on: events("press")).context).showsRemove)
    }

    @Test("Chip colours: grey, a custom background, or indigo when selected")
    func chipColours() throws {
        let plain = try ChipComponent.Model(render("Chip", ["label": "Tag"]).context)
        #expect(plain.backgroundColor == .css("#f3f4f6"))
        #expect(plain.textColor == .css("#374151"))
        #expect(try ChipComponent.Model(render("Chip", ["label": "Tag", "backgroundColor": "#00ff00"]).context).backgroundColor == .css("lime"))
        let selected = try ChipComponent.Model(render("Chip", ["label": "Tag", "selected": true, "backgroundColor": "#00ff00"]).context)
        #expect(selected.backgroundColor == .css("#6366f1"))
        #expect(selected.textColor == .css("#ffffff"))
    }
}
