import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const compiler = fileURLToPath(new URL('../../test/scratch/site-tooling/node_modules/typescript/bin/tsc', import.meta.url));
const config = fileURLToPath(new URL('../tsconfig.json', import.meta.url));
const result = spawnSync(process.execPath, [compiler, '--project', config, '--noEmit'], { stdio: 'inherit' });
if (result.status === 0) console.log('Typecheck passed: app, config, wallet, wheel, NFT voxels and garage (checkJs, noEmit).');
process.exitCode = result.status ?? 1;
