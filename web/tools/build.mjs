// Production export only: browser source is already plain HTML, CSS, and JavaScript.
import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { basename, join } from 'node:path';
import { createHash } from 'node:crypto';
import { CONFIG } from '../config.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const web = join(root, 'web'), dist = join(root, 'dist');
const deployment = JSON.parse(await readFile(join(root, 'burrow_deployed.json'), 'utf8'));
for (const [key, contract] of Object.entries(deployment.contracts)) {
  if (CONFIG.burrow[key] !== contract.address) throw new Error(`Address mismatch: ${key}`);
  for (const [path, record] of Object.entries(contract.sources)) {
    const sha = createHash('sha256').update(await readFile(join(root, path))).digest('hex');
    if (sha !== record.sha256) throw new Error(`Source differs from verified deployment: ${path}`);
  }
}
await rm(dist, { recursive: true, force: true });
await mkdir(join(dist, 'source'), { recursive: true });
for (const name of ['index.html', 'styles.css', 'app.js', 'config.js', 'wallet.js', 'wheel.js', 'assets', 'licenses']) {
  await cp(join(web, name), join(dist, name), { recursive: true });
}
await mkdir(join(dist, 'vendor'));
for (const name of ['three.module.min.js', 'coinbase.js']) await cp(join(web, 'vendor', name), join(dist, 'vendor', name));
await cp(join(root, 'burrow_deployed.json'), join(dist, 'source', 'burrow_deployed.json'));

const esc = text => String(text).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function page(title, body) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)} · Burrow source</title><meta name="description" content="Burrow v2 source, tests and deployment record"><link rel="icon" href="../assets/favicon.svg"><link rel="stylesheet" href="../styles.css"><style>pre{background:var(--sunk);border:1px solid var(--line);border-radius:8px;padding:16px;overflow:auto;font:12px/18px var(--mono);tab-size:4}.wrap{max-width:1100px}.source-address{overflow-wrap:anywhere;white-space:normal}.source-table{overflow:auto}.source-table a{display:inline-block;min-height:24px}.source-list a{border:0}.source-header{flex-wrap:wrap;height:auto;min-height:64px;gap:8px;padding-block:12px}.source-header .chip{white-space:normal}</style></head><body><header class="top"><div class="topin source-header"><a class="brand" href="../index.html" style="border:0">Burrow</a><span class="chip">source, exactly what is deployed</span><span class="sp"></span><a class="chip" href="./index.html">all files</a></div></header><main class="wrap">${body}</main></body></html>\n`;
}
const files = ['README.md', ...await readdir(join(root, 'src')).then(names => names.filter(n => n.endsWith('.sol')).map(n => 'src/' + n)),
  ...await readdir(join(root, 'test')).then(names => names.filter(n => n.endsWith('.sol')).map(n => 'test/' + n))];
const fileRows = [];
for (const path of files) {
  const name = basename(path).replace(/\.(sol|md)$/, ''), text = await readFile(join(root, path), 'utf8');
  await writeFile(join(dist, 'source', name + '.html'), page(path, `<section class="panel"><div class="ph"><h1 style="font-size:16px">${esc(path)}</h1></div><pre tabindex="0" aria-label="${esc(path)} source"><code>${esc(text)}</code></pre></section>`));
  fileRows.push(`<tr><td><a href="./${name}.html">${esc(path)}</a></td><td class="n muted">${text.split('\n').length} lines</td></tr>`);
}
const contractRows = Object.values(deployment.contracts).map(c => {
  const path = Object.keys(c.sources)[0], name = basename(path, '.sol');
  return `<tr><td><a href="./${name}.html">${name}.sol</a></td><td class="n"><a class="source-address" href="${CONFIG.explorer}/address/${c.address}">${c.address}</a></td><td><a href="https://sourcify.dev/server/v2/contract/11155111/${c.address}?fields=all">Sourcify</a></td></tr>`;
});
await writeFile(join(dist, 'source', 'index.html'), page('Source', `<section class="panel"><div class="ph"><h1 style="font-size:16px">Verified source</h1><span class="hint">Sepolia, Sourcify exact match</span></div><div class="source-table" tabindex="0" role="region" aria-label="Verified contracts"><table><thead><tr><th>Contract</th><th>Address</th><th>Verified</th></tr></thead><tbody>${contractRows.join('')}</tbody></table></div></section><section class="panel" style="margin-top:20px"><div class="ph"><h2>Files</h2><span class="hint">src, test, README</span></div><table><tbody class="source-list">${fileRows.join('')}<tr><td><a href="./burrow_deployed.json">Deployment record (JSON)</a></td><td></td></tr></tbody></table></section><p class="muted" style="margin:16px 0 48px">The four protocol sources in this repository match the deployed contracts verified by Sourcify. Tests and documentation are included for review.</p>`));
async function size(dir) {
  let bytes = 0, count = 0;
  for (const f of await readdir(dir, { withFileTypes: true })) {
    if (f.isDirectory()) { const s = await size(join(dir, f.name)); bytes += s.bytes; count += s.count; }
    else { bytes += (await readFile(join(dir, f.name))).byteLength; count++; }
  }
  return { bytes, count };
}
console.log('Production export:', JSON.stringify(await size(dist)), '— dist/ (relative assets, no network/build dependencies).');
