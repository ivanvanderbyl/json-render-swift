// Exports a json-render catalog as JSON for the Swift renderer: each
// component's props and each action's params become JSON Schema, written with
// io: "input" so the Swift validator accepts and rejects what zod does.
//
// Hosts can copy this function into their TypeScript build and ship the
// output with their app, then load it with Catalog(manifest:schema:).

import { z } from "zod";

export function exportCatalog(catalog) {
  const { components = {}, actions = {}, functions } = catalog.data;
  const manifest = {
    components: Object.fromEntries(
      Object.entries(components).map(([name, definition]) => [name, exportEntry(definition, "props")]),
    ),
    actions: Object.fromEntries(
      Object.entries(actions).map(([name, definition]) => [name, exportEntry(definition, "params")]),
    ),
  };
  if (functions) manifest.functions = Object.keys(functions);
  return manifest;
}

function exportEntry(definition, schemaKey) {
  const entry = {};
  for (const [key, value] of Object.entries(definition)) {
    if (key === schemaKey) {
      entry[key] = z.toJSONSchema(value, { io: "input" });
    } else if (value !== undefined) {
      entry[key] = value;
    }
  }
  return entry;
}
