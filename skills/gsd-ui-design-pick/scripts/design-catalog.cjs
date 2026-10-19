#!/usr/bin/env node
// Parse a directory of DESIGN.md templates (awesome-design-md layout: <dir>/<id>/DESIGN.md).
// Usage: node design-catalog.cjs <design-md-dir>   -> JSON array on stdout
const fs = require("fs"), path = require("path");
const root = process.argv[2];
if (!root || !fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  console.error("Usage: node design-catalog.cjs <design-md-dir>");
  process.exit(2);
}
const lum = h => { h = h.replace("#", ""); if (h.length === 3) h = h.split("").map(c => c + c).join("");
  const c = h.match(/../g).map(x => { x = parseInt(x, 16) / 255; return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const out = [];
for (const d of fs.readdirSync(root).sort()) {
  const f = path.join(root, d, "DESIGN.md"); if (!fs.existsSync(f)) continue;
  const s = fs.readFileSync(f, "utf8").replace(/\r\n/g, "\n"); const fm = (s.match(/^---\n([\s\S]*?)\n---/) || [])[1] || "";
  const color = k => (fm.match(new RegExp("^\\s*" + k + ":\\s*\"?(#[0-9a-fA-F]{3,6})", "m")) || [])[1] || null;
  const canvas = color("canvas") || color("background") || color("surface");
  const fonts = [...new Set([...fm.matchAll(/fontFamily:\s*([^,\n]+)/g)].map(m => m[1].trim().replace(/["']/g, "")))];
  const sections = [...s.matchAll(/^##\s+(.+)$/gm)].map(m => m[1].trim());
  out.push({
    id: d,
    name: (fm.match(/^name:\s*(.*)$/m) || [])[1] || d,
    description: (fm.match(/^description:\s*(.*)$/m) || [])[1] || "",
    primary: color("primary"), canvas,
    darkCanvas: canvas ? lum(canvas) < 0.2 : null,
    colorCount: ((fm.match(/^colors:\n([\s\S]*?)\n\S/m) || [])[1] || "").split("\n").filter(Boolean).length,
    fonts,
    hasSemantic: /positive|success|negative|error|danger|warning/i.test(fm),
    hasDarkMode: /dark[- ]mode/i.test(s),
    sections, bytes: s.length
  });
}
out.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
console.log(JSON.stringify(out, null, 1));
