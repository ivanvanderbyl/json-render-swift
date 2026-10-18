// Runs every corpus file through the pinned upstream packages and writes one
// golden file per suite. With --check, fails instead of writing when a golden
// is missing or differs, so a stale golden is caught before the Swift tests.

import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const corpusDir = path.join(root, "corpus");
const goldenDir = path.join(root, "goldens");
const suiteDir = path.join(here, "suites");
const check = process.argv.includes("--check");
const only = process.argv.find((arg) => arg.startsWith("--suite="))?.slice(8);

const pinned = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
const upstream = {};
for (const name of ["@json-render/core", "@json-render/react", "@json-render/react-native", "zod", "react", "react-dom"]) {
  const installed = JSON.parse(await readFile(path.join(root, "node_modules", name, "package.json"), "utf8")).version;
  if (installed !== pinned.dependencies[name]) {
    throw new Error(`${name} ${installed} is installed but ${pinned.dependencies[name]} is pinned; run pnpm install --frozen-lockfile`);
  }
  upstream[name] = installed;
}

const suites = (await readdir(suiteDir)).filter((file) => file.endsWith(".mjs")).sort();
const manifest = { upstream, suites: {} };
let stale = 0;

for (const file of suites) {
  const name = file.replace(/\.mjs$/, "");
  const corpusText = await readFile(path.join(corpusDir, `${name}.json`), "utf8");
  const corpusSHA256 = createHash("sha256").update(corpusText).digest("hex");
  manifest.suites[name] = { corpusSHA256 };
  if (only && only !== name) continue;

  const suite = await import(pathToFileURL(path.join(suiteDir, file)).href);
  const corpus = JSON.parse(corpusText);
  const cases = [];
  for (const entry of corpus.cases) {
    cases.push({ name: entry.name, output: await suite.run(entry, corpus) });
  }
  const golden = `${JSON.stringify({ suite: name, upstream, corpusSHA256, cases }, null, 2)}\n`;
  stale += await emit(path.join(goldenDir, `${name}.json`), golden);
}

if (!only) {
  stale += await emit(path.join(goldenDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
}
if (check && stale > 0) {
  console.error(`${stale} golden file(s) are out of date. Run: make goldens`);
  process.exit(1);
}

async function emit(file, content) {
  const previous = await readFile(file, "utf8").catch(() => undefined);
  if (previous === content) return 0;
  if (check) {
    console.error(`stale: ${path.relative(root, file)}`);
    return 1;
  }
  await writeFile(file, content);
  console.log(`wrote ${path.relative(root, file)}`);
  return 0;
}
