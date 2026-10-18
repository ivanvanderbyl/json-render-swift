// Catalogs and catalog.validate() from @json-render/core, using the React and
// React Native renderer schemas. The golden carries the exported manifest the
// Swift tests load, the catalog's names, and the validation verdicts.

import { defineCatalog, defineSchema } from "@json-render/core";
import { schema as reactSchema } from "@json-render/react";
import { schema as reactNativeSchema } from "@json-render/react-native";
import { decode, encode } from "../encoding.mjs";
import { exportCatalog } from "../export-catalog.mjs";
import { build, issues } from "../zod-dsl.mjs";

// Mirrors the shared test schema in upstream schema.test.ts.
const testSchema = defineSchema((s) => ({
  spec: s.object({
    root: s.string(),
    elements: s.record(
      s.object({
        type: s.ref("catalog.components"),
        props: s.propsOf("catalog.components"),
        children: s.array(s.string()),
        slots: { ...s.record(s.array(s.string())), ...s.optional() },
        visible: { ...s.any(), ...s.optional() },
      }),
    ),
  }),
  catalog: s.object({
    components: s.map({ props: s.zod(), slots: s.array(s.string()), description: s.string(), example: s.any() }),
    actions: s.map({ description: s.string() }),
  }),
}));

const schemas = { react: reactSchema, "react-native": reactNativeSchema, test: testSchema };

function definitions(raw = {}, schemaKey) {
  return Object.fromEntries(
    Object.entries(raw).map(([name, definition]) => [
      name,
      Object.fromEntries(
        Object.entries(definition).map(([key, value]) => [key, key === schemaKey ? build(value) : value]),
      ),
    ]),
  );
}

export function run(entry) {
  const catalog = defineCatalog(schemas[entry.schema], {
    components: definitions(entry.components, "props"),
    actions: definitions(entry.actions, "params"),
  });
  return {
    manifest: exportCatalog(catalog),
    componentNames: catalog.componentNames,
    actionNames: catalog.actionNames,
    results: entry.specs.map((raw) => {
      const result = catalog.validate(decode(raw));
      return result.success
        ? { success: true, data: encode(result.data) }
        : { success: false, issues: issues(result.error) };
    }),
  };
}
