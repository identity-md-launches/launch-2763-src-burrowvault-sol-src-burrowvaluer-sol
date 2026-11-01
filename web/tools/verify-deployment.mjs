// Read-only checks against the named public deployment. Never sends transactions.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { CONFIG as C } from '../config.js';
const root = fileURLToPath(new URL('../../', import.meta.url));
const record = JSON.parse(await readFile(join(root, 'burrow_deployed.json'), 'utf8'));
const app = await readFile(join(root, 'web/app.js'), 'utf8');
function mapFor(name) {
  const block = app.match(new RegExp('const ' + name + ' = \\{([\\s\\S]*?)\\};'))?.[1] || '';
  return Object.fromEntries([...block.matchAll(/(\w+):'(0x[0-9a-f]+)'/g)].map(match => [match[1], match[2]]));
}
const selectors = mapFor('SEL'), topics = mapFor('TOPIC');
const hs = mapFor('HS'), bs = mapFor('BS'), gs = mapFor('GS');
const perContract = {
  wheelBond: { lock:bs.lock, redeem:bs.redeem, exitEarly:bs.exit, bonds:bs.bonds, bonusOf:bs.bonusOf, work:bs.work, nextId:bs.nextId },
  hmtr: { ...hs, balanceOf:selectors.balanceOf, totalSupply:selectors.totalSupply, allowance:selectors.allowance, approve:selectors.approve },
  garage: { park:gs.park, claimCar:gs.claim, leave:gs.leave, spots:gs.spots, valueOf:gs.value, readyAt:gs.ready, nextSpot:gs.nextSpot, nextCar:gs.nextCar },
};
const usedInValuer = new Set(['pricePerPower', 'ltvBps', 'lastPriceChange', 'powerForLevel']);
async function rpc(method, params) {
  let last;
  for (const url of C.rpcs) {
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(15000), body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) });
      const j = await r.json(); if (!r.ok || j.error || !('result' in j)) throw new Error(j.error?.message || 'RPC unavailable'); return j.result;
    } catch (e) { last = e; }
  }
  throw last;
}
const results = await Promise.all(Object.entries(record.contracts).map(async ([name, entry]) => {
  const url = `https://sourcify.dev/server/v2/contract/${C.chainId}/${entry.address}?fields=all`;
  const r = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!r.ok) throw new Error(`Sourcify ${name}: HTTP ${r.status}`);
  const contract = await r.json();
  const sources = [];
  for (const [path, expected] of Object.entries(entry.sources)) {
    const local = await readFile(join(root, path), 'utf8'), live = contract.sources[path].content;
    const sha = createHash('sha256').update(local).digest('hex');
    sources.push({ path, identical: local === live && sha === expected.sha256, sha256: sha });
  }
  const checkedSelectors = [];
  if (['vault', 'valuer'].includes(name)) for (const signature of contract.signatures.function) {
    const method = signature.signature.split('(')[0];
    if (!(method in selectors) || (name === 'valuer') !== usedInValuer.has(method)) continue;
    checkedSelectors.push({ signature: signature.signature, matches: selectors[method] === signature.signatureHash4 });
  }
  if (perContract[name]) for (const signature of contract.signatures.function) {
    const method = signature.signature.split('(')[0];
    if (method in perContract[name]) checkedSelectors.push({ signature: signature.signature, matches: perContract[name][method] === signature.signatureHash4 });
  }
  if (['vault','wheelBond','garage'].includes(name)) for (const event of contract.signatures.event) {
    const eventName = event.signature.split('(')[0].toLowerCase();
    const value = name === 'garage' ? (eventName === 'parked' ? gs.parked : null) : name === 'wheelBond' ? (eventName === 'locked' ? topics.locked : null) : topics[eventName];
    if (value) checkedSelectors.push({ signature: event.signature, matches: value === event.signatureHash32 });
  }
  let chain;
  try {
    const [code, receipt] = await Promise.all([rpc('eth_getCode', [entry.address, 'latest']), rpc('eth_getTransactionReceipt', [entry.deployment.transactionHash])]);
    chain = { runtimeBytes: (code.length - 2) / 2, gasUsed: Number(BigInt(receipt.gasUsed)), gasUnderCap: BigInt(receipt.gasUsed) <= 16777216n, deploymentSucceeded: receipt.status === '0x1' };
  } catch (e) { chain = { limitation: 'Public RPC check unavailable: ' + e.message }; }
  return { name, address: entry.address, source: url, match: contract.match, creationMatch: contract.creationMatch, runtimeMatch: contract.runtimeMatch, sources, checkedSelectors, chain };
}));
const ok = results.every(r => r.match === 'exact_match' && r.creationMatch === 'exact_match' && r.runtimeMatch === 'exact_match' && r.sources.every(s => s.identical) && r.checkedSelectors.every(s => s.matches) && (!('gasUnderCap' in r.chain) || (r.chain.gasUnderCap && r.chain.deploymentSucceeded)));
await mkdir(join(root, 'web/validation'), { recursive: true });
await writeFile(join(root, 'web/validation/deployment-verification.json'), JSON.stringify({ checkedAt: new Date().toISOString(), passed: ok, results }, null, 2) + '\n');
console.log(JSON.stringify({ passed: ok, contracts: results.map(r => ({ name: r.name, exact: r.match, sourceMatches: r.sources.every(s => s.identical), selectorsChecked: r.checkedSelectors.length, chain: r.chain })) }, null, 2));
if (!ok) process.exitCode = 1;
