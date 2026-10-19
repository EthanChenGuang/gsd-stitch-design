#!/usr/bin/env node
// WCAG contrast ratio. Usage: node contrast.cjs <fg> <bg> [--json]
// Colors are hex with or without "#", 3 or 6 digits, any case.
'use strict';

const USAGE = 'Usage: node contrast.cjs <fg> <bg> [--json]\n  e.g. node contrast.cjs "#1A1A1A" "#FFFFFF"';

function parseHex(input) {
  let h = String(input).trim().replace(/^#/, '');
  if (!/^([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(h)) return null;
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  return h;
}

function luminance(h) {
  const c = h.match(/../g).map((x) => {
    const v = parseInt(x, 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

const args = process.argv.slice(2);
const json = args.includes('--json');
const colors = args.filter((a) => a !== '--json');
if (colors.length !== 2) {
  console.error(USAGE);
  process.exit(2);
}
const fg = parseHex(colors[0]);
const bg = parseHex(colors[1]);
if (!fg || !bg) {
  console.error('Invalid hex color: ' + (!fg ? colors[0] : colors[1]));
  console.error(USAGE);
  process.exit(2);
}

const a = luminance(fg);
const b = luminance(bg);
const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
const res = {
  fg: '#' + fg.toUpperCase(),
  bg: '#' + bg.toUpperCase(),
  ratio: Number(ratio.toFixed(2)),
  AA: ratio >= 4.5,
  AA_large: ratio >= 3,
  AAA: ratio >= 7,
  AAA_large: ratio >= 4.5,
};
const pf = (v) => (v ? 'pass' : 'fail');

if (json) {
  console.log(JSON.stringify(res));
} else {
  console.log(
    `${ratio.toFixed(2)}:1  AA:${pf(res.AA)}  AA-large:${pf(res.AA_large)}  AAA:${pf(res.AAA)}  AAA-large:${pf(res.AAA_large)}`
  );
}
