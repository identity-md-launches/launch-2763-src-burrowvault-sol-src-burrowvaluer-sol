import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.woff2': 'font/woff2', '.json': 'application/json', '.txt': 'text/plain' };
export function previewServer(root) {
  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname === '/') { res.writeHead(302, { location: '/preview/' }); res.end(); return; }
      if (!url.pathname.startsWith('/preview/')) { res.writeHead(404); res.end('Not found'); return; }
      let path = resolve(root, '.' + decodeURIComponent(url.pathname.slice('/preview'.length)));
      if (path !== resolve(root) && !path.startsWith(resolve(root) + sep)) throw new Error('Invalid path');
      if ((await stat(path)).isDirectory()) path = resolve(path, 'index.html');
      const data = await readFile(path);
      res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream', 'Cache-Control': 'no-store', 'Content-Security-Policy': "script-src 'self'; object-src 'none'; base-uri 'self'" }); res.end(data);
    } catch { res.writeHead(404); res.end('Not found'); }
  });
}
