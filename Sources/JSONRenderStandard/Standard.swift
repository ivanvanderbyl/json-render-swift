import JSONRender

/// The React Native standard catalog, like upstream
/// `standardComponentDefinitions` and `standardActionDefinitions`, with the
/// React Native renderer schema.
///
/// The definitions are upstream's own, exported to JSON Schema and embedded
/// (see `StandardCatalogManifest`), so props and params accept and reject
/// what upstream's zod schemas do. Every nullable prop is a required key:
/// `{ "level": null }` is valid where a missing `level` is not.
public enum StandardCatalog {
    /// The catalog of the 26 standard components and 9 standard actions.
    public static let catalog: Catalog = {
        do {
            return try Catalog(manifest: JSONValue(parsing: StandardCatalogManifest.json), schema: .reactNative)
        } catch {
            preconditionFailure("The embedded standard catalog manifest is invalid: \(error)")
        }
    }()

    /// Component definitions by name, like `standardComponentDefinitions`.
    public static var components: [String: ComponentDefinition] { catalog.components }
    /// Action definitions by name, like `standardActionDefinitions`.
    public static var actions: [String: ActionDefinition] { catalog.actions }
}
