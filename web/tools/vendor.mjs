// Optional, reproducible refresh of the committed browser libraries. Serving/building needs no npm.
import { build } from '../../test/scratch/site-tooling/node_modules/esbuild/lib/main.js';
import { copyFile, readdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
const web = fileURLToPath(new URL('../', import.meta.url));
const modules = fileURLToPath(new URL('../../test/scratch/site-tooling/node_modules/', import.meta.url));
await copyFile(join(modules, 'three/build/three.module.min.js'), join(web, 'vendor/three.module.min.js'));
await copyFile(join(modules, 'three/LICENSE'), join(web, 'licenses/Three-MIT.txt'));
await build({
  entryPoints: [join(modules, '@coinbase/wallet-sdk/dist/index.js')],
  outfile: join(web, 'vendor/coinbase.js'), bundle: true, format: 'esm',
  platform: 'browser', target: 'es2022', minify: true, legalComments: 'eof',
  define: { 'process.env.NODE_ENV': '"production"' },
});
// Keep license texts for every SDK dependency; no package archives or caches are copied.
const notices = [];
async function collect(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    const path = join(dir, entry.name);
    if (entry.name.startsWith('@')) { await collect(path); continue; }
    const meta = await readFile(join(path, 'package.json'), 'utf8').then(JSON.parse).catch(() => null);
    if (!meta || /^(playwright|playwright-core|typescript|esbuild|three)$/.test(meta.name) || meta.name.startsWith('@types/') || meta.name.startsWith('@esbuild/')) continue;
    for (const name of await readdir(path)) if (/^(licen[cs]e|copying)(\.|$)/i.test(name)) {
      notices.push(`\n===== ${meta.name}@${meta.version} — ${name} =====\n${await readFile(join(path, name), 'utf8')}`);
    }
  }
}
await collect(modules);
await writeFile(join(web, 'licenses/Coinbase-dependencies.txt'), notices.sort().join('\n'));
console.log('Browser libraries regenerated from web/package-lock.json.');
