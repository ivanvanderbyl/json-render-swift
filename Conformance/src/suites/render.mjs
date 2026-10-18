// Full render scenarios through @json-render/react: JSONUIProvider and
// Renderer in jsdom. See src/render/harness.mjs for the recorded shape.

import { runScenario } from "../render/harness.mjs";

export function run(entry) {
  return runScenario(entry);
}
