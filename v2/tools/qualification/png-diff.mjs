#!/usr/bin/env node
// Contrôle visuel sans vision : décode deux PNG (8 bit RGBA/RGB, non interlacé — format de VBoxManage screenshotpng)
// et rapporte le pourcentage de pixels changés + bornes. Sert à prouver qu'une frappe a (ou non) modifié l'écran.
import { readFileSync } from 'node:fs';
import { inflateSync } from 'node:zlib';

function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('pas un PNG');
  let pos = 8, w = 0, h = 0, bitDepth = 0, colorType = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); bitDepth = data[8]; colorType = data[9];
      if (bitDepth !== 8 || data[12] !== 0) throw new Error('PNG non supporté depth=' + bitDepth + ' interlace=' + data[12]); }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : colorType === 0 ? 1 : colorType === 4 ? 2 : (() => { throw new Error('colorType ' + colorType); })();
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * channels;
  const out = Buffer.alloc(h * stride);
  let rp = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[rp++];
    const line = raw.subarray(rp, rp + stride); rp += stride;
    const cur = out.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? cur[x - channels] : 0, b = prev[x], c = x >= channels ? prev[x - channels] : 0;
      let v = line[x];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); }
      cur[x] = v & 0xff;
    }
  }
  return { w, h, channels, data: out };
}

const [a, b] = process.argv.slice(2);
const A = decodePng(readFileSync(a)), B = decodePng(readFileSync(b));
if (A.w !== B.w || A.h !== B.h) { console.log(JSON.stringify({ diff: 'DIMENSIONS', a: [A.w, A.h], b: [B.w, B.h] })); process.exit(0); }
let changed = 0, minX = A.w, minY = A.h, maxX = -1, maxY = -1;
const total = A.w * A.h;
for (let i = 0; i < total; i++) {
  const o = i * A.channels;
  let d = false;
  for (let c = 0; c < A.channels; c++) if (A.data[o + c] !== B.data[o + c]) { d = true; break; }
  if (d) { changed++; const x = i % A.w, y = (i / A.w) | 0;
    if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
}
console.log(JSON.stringify({ w: A.w, h: A.h, total, changed, pct: +(100 * changed / total).toFixed(3),
  bbox: changed ? [minX, minY, maxX, maxY] : null }));
