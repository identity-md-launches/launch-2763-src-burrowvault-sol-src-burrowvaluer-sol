import { fileURLToPath } from 'node:url';
import { previewServer } from './server.mjs';
const server = previewServer(fileURLToPath(new URL('../../dist/', import.meta.url)));
const port = Number(process.argv[2] || 4173);
server.listen(port, '0.0.0.0', () => console.log(`Burrow preview: http://localhost:${port}/preview/ (Ctrl-C to stop)`));
