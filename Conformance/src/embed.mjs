// Writes the Swift sources that embed upstream documents, from the goldens:
// the JSON Schema exports of core's zod schemas, and the React Native
// standard catalog manifest. With --check, fails instead of writing when a
// source is out of date.

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const packageRoot = path.resolve(root, "..");
const check = process.argv.includes("--check");

async function golden(suite) {
  return JSON.parse(await readFile(path.join(root, "goldens", `${suite}.json`), "utf8"));
}

function literal(value) {
  return `#"""\n${JSON.stringify(value)}\n"""#`;
}

const schemas = await golden("upstream-schemas");
const versions = schemas.upstream;
const documents = schemas.cases
  .map(({ name, output }) => {
    const property = name.replace(/Schema$/, "").replace(/^./, (c) => c.toLowerCase());
    return `    /// \`${name}\`.\n    static let ${property} = ${literal(output)}\n`;
  })
  .join("\n");
const schemaSource = `// Generated from the zod schemas @json-render/core ${versions["@json-render/core"]} exports, as
// JSON Schema with io "input" (see Conformance/src/suites/upstream-schemas.mjs).
// ConformanceTests checks these documents still match upstream.

/// The JSON Schema form of upstream zod schemas.
enum UpstreamSchemaDocuments {
${documents}}
`;

const standard = await golden("standard-catalog");
const manifest = standard.cases.find((entry) => entry.name === "manifest").output.manifest;
const standardSource = `// Generated from standardComponentDefinitions and standardActionDefinitions in
// @json-render/react-native ${versions["@json-render/react-native"]}, exported with
// Conformance/src/export-catalog.mjs (see Conformance/src/suites/standard-catalog.mjs).
// ConformanceTests checks this manifest still matches upstream.

enum StandardCatalogManifest {
    static let json = ${literal(manifest)}
}
`;

let stale = 0;
for (const [file, content] of [
  ["Sources/JSONRender/UpstreamSchemaDocuments.swift", schemaSource],
  ["Sources/JSONRenderStandard/StandardCatalogManifest.swift", standardSource],
]) {
  const target = path.join(packageRoot, file);
  const previous = await readFile(target, "utf8").catch(() => undefined);
  if (previous === content) continue;
  if (check) {
    console.error(`stale: ${file}`);
    stale += 1;
  } else {
    await writeFile(target, content);
    console.log(`wrote ${file}`);
  }
}
if (stale > 0) {
  console.error(`${stale} embedded document(s) are out of date. Run: make goldens`);
  process.exit(1);
}
