// The React Native standard catalog: standardComponentDefinitions and
// standardActionDefinitions from @json-render/react-native, exported as the
// manifest the Swift package embeds, plus zod's verdicts on sample props,
// action params and specs.

import { defineCatalog } from "@json-render/core";
import {
  schema,
  standardActionDefinitions,
  standardComponentDefinitions,
} from "@json-render/react-native";
import { decode, encode } from "../encoding.mjs";
import { exportCatalog } from "../export-catalog.mjs";
import { issues } from "../zod-dsl.mjs";

const catalog = defineCatalog(schema, {
  components: standardComponentDefinitions,
  actions: standardActionDefinitions,
});

function verdict(result) {
  return result.success
    ? { success: true, data: encode(result.data) }
    : { success: false, issues: issues(result.error) };
}

export function run(entry) {
  switch (entry.op) {
    case "manifest":
      return { manifest: exportCatalog(catalog), componentNames: catalog.componentNames, actionNames: catalog.actionNames };
    case "props":
      return verdict(standardComponentDefinitions[entry.component].props.safeParse(decode(entry.value)));
    case "params":
      return verdict(standardActionDefinitions[entry.action].params.safeParse(decode(entry.value)));
    case "spec":
      return verdict(catalog.validate(decode(entry.spec)));
    default:
      throw new Error(`unknown op ${entry.op}`);
  }
}
