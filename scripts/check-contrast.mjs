import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const css = readFileSync(new URL("../site/styles.css", import.meta.url), "utf8");
const colors = Object.fromEntries(
  [...css.matchAll(/--color-([a-z]+):\s*(#[0-9a-f]{6})\s*;/gi)].map(([, name, value]) => [name, value])
);

function luminance(hex) {
  return [1, 3, 5].reduce((sum, offset, index) => {
    const channel = Number.parseInt(hex.slice(offset, offset + 2), 16) / 255;
    const linear = channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    return sum + linear * [0.2126, 0.7152, 0.0722][index];
  }, 0);
}

for (const [foreground, background] of [
  ["paper", "ink"], ["paper", "board"],
  ["muted", "ink"], ["muted", "board"],
  ["copper", "ink"], ["copper", "board"],
  ["ink", "copper"]
]) {
  assert.ok(colors[foreground] && colors[background], `Missing ${foreground}/${background} color`);
  const values = [luminance(colors[foreground]), luminance(colors[background])].sort((a, b) => b - a);
  const ratio = (values[0] + 0.05) / (values[1] + 0.05);
  assert.ok(ratio >= 4.5, `${foreground}/${background} contrast ${ratio.toFixed(2)} is below 4.5`);
  console.log(`${foreground}/${background}: ${ratio.toFixed(2)}`);
}
