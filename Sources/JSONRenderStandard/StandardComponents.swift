import JSONRender
import JSONRenderUI
import SwiftUI

/// The SwiftUI versions of upstream `standardComponents` from
/// @json-render/react-native, by type name.
public enum StandardComponents {
    @MainActor public static let all: [String: Component] = [
        // Layout
        "Container": Component { ContainerComponent($0) },
        "Row": Component { RowComponent($0) },
        "Column": Component { ColumnComponent($0) },
        "ScrollContainer": Component { ScrollContainerComponent($0) },
        "SafeArea": Component { SafeAreaComponent($0) },
        "Pressable": Component { PressableComponent($0) },
        "Spacer": Component { SpacerComponent($0) },
        "Divider": Component { DividerComponent($0) },
        // Content
        "Heading": Component { try HeadingComponent($0) },
        "Paragraph": Component { try ParagraphComponent($0) },
        "Label": Component { try LabelComponent($0) },
        "Image": Component { ImageComponent($0) },
        "Avatar": Component { try AvatarComponent($0) },
        "Badge": Component { try BadgeComponent($0) },
        "Chip": Component { try ChipComponent($0) },
        // Input
        "Button": Component { try ButtonComponent($0) },
        "TextInput": Component { try TextInputComponent($0) },
        "Switch": Component { try SwitchComponent($0) },
        "Checkbox": Component { try CheckboxComponent($0) },
        "Slider": Component { try SliderComponent($0) },
        "SearchBar": Component { try SearchBarComponent($0) },
        // Feedback
        "Spinner": Component { SpinnerComponent($0) },
        "ProgressBar": Component { ProgressBarComponent($0) },
        // Composite
        "Card": Component { try CardComponent($0) },
        "ListItem": Component { try ListItemComponent($0) },
        "Modal": Component { try ModalComponent($0) },
    ]
}

extension Registry {
    /// A registry of the standard components for the standard catalog.
    @MainActor public static let standard = Registry(catalog: StandardCatalog.catalog, components: StandardComponents.all)

    /// This registry with the standard components added under its own, like
    /// upstream's `Renderer` with `includeStandard` (the default): a host
    /// component replaces a standard one of the same name.
    @MainActor public func includingStandard() -> Registry {
        Registry.standard.merging(self)
    }
}
