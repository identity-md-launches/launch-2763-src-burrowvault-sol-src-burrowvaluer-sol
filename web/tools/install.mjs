// Tooling lives only in disposable scratch space, never in the submission.
import { mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const web = fileURLToPath(new URL('../', import.meta.url));
const scratch = fileURLToPath(new URL('../../test/scratch/site-tooling/', import.meta.url));
await mkdir(scratch, { recursive: true });
for (const file of ['package.json', 'package-lock.json']) await copyFile(join(web, file), join(scratch, file));
const result = spawnSync('npm', ['ci', '--prefix', scratch, '--cache', join(tmpdir(), 'burrow-npm-cache'), '--no-audit', '--no-fund'], { stdio: 'inherit' });
process.exitCode = result.status ?? 1;
