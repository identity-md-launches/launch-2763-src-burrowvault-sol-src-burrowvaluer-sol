// Static export integrity: all runtime assets are local and survive the pinned exporter.
import { readFile, readdir, stat } from 'node:fs/promises';
import { resolve, relative, dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
export async function checkExport(directory) {
  const root = resolve(directory), files = [];
  async function walk(dir) {
    for (const item of await readdir(dir, { withFileTypes: true })) {
      if (item.isSymbolicLink()) throw new Error('Export cannot contain symlinks: ' + item.name);
      const path = join(dir, item.name);
      if (item.isDirectory()) {
        if (['vendor', 'node_modules'].includes(item.name)) throw new Error('Forbidden runtime directory: ' + path);
        await walk(path);
      } else files.push(path);
    }
  }
  await walk(root);
  let references = 0;
  async function local(value, file) {
    if (!value || /^(?:https?:|data:|mailto:|#)/.test(value)) return;
    if (/^(?:\/|[a-z]+:)/i.test(value)) throw new Error('Asset must be relative: ' + value);
    const path = resolve(dirname(file), decodeURIComponent(value.split(/[?#]/)[0]));
    if (path !== root && !path.startsWith(root + sep)) throw new Error('Asset escapes export: ' + value);
    const target = await stat(path).catch(() => null);
    if (!target || (!target.isFile() && !await stat(join(path, 'index.html')).catch(() => null))) throw new Error('Missing asset from ' + relative(root, file) + ': ' + value);
    references++;
  }
  for (const file of files) {
    if (/\.(?:tgz|map)$/.test(file) || /(?:package(?:-lock)?\.json|\.d\.ts)$/.test(file)) throw new Error('Unnecessary packaging file: ' + file);
    if (!/\.(?:html|css|js)$/.test(file)) continue;
    const text = await readFile(file, 'utf8');
    if (file.endsWith('.html')) {
      // Ignore code listings, which contain escaped source, and inspect actual markup only.
      for (const match of text.matchAll(/<(?:script|link|img|source)\b[^>]*>/gi)) {
        const tag = match[0];
        for (const [, value] of tag.matchAll(/(?:src|href)=["']([^"']+)["']/g)) {
          if (/^<script/i.test(tag) && /^https?:|^\/\//.test(value)) throw new Error('External runtime script: ' + value);
          await local(value, file);
        }
      }
      if (/<script\b(?![^>]*\bsrc=)[^>]*>\s*\S/i.test(text)) throw new Error('Inline script blocked by script-src self: ' + file);
      for (const [, value] of text.matchAll(/<a\b[^>]*\bhref=["']([^"']+)["']/g)) await local(value, file);
      for (const [, value] of text.matchAll(/<meta\b[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/g)) await local(value, file);
    }
    if (file.endsWith('.css')) for (const [, value] of text.matchAll(/url\(["']?([^\s"')]+)["']?\)/g)) await local(value, file);
    if (file.endsWith('.js')) for (const [, value] of text.replace(/\/\*\*[\s\S]*?\*\//g, '').matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*)["'](\.[^"']+)["']/g)) await local(value, file);
  }
  const report = { files: files.length, references, bytes: (await Promise.all(files.map(file => stat(file)))).reduce((sum, file) => sum + file.size, 0) };
  console.log('Export integrity passed:', JSON.stringify(report));
  return report;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) await checkExport(process.argv[2] || 'dist');
