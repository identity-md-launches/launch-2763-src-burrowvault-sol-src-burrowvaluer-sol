// Deterministic interaction tests. Mock providers never broadcast a transaction.
// All mock chain state belongs only to this test process, never the static export.
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { chromium, webkit } from '../../test/scratch/site-tooling/node_modules/playwright/index.mjs';
import { decodeFunctionData, encodeFunctionData, encodeAbiParameters, keccak256, toHex } from '../../test/scratch/site-tooling/node_modules/viem/_esm/index.js';
import { previewServer } from './server.mjs';
import { CONFIG as C } from '../config.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const fixture = JSON.parse(await readFile(new URL('./feed-fixture.json', import.meta.url), 'utf8'));
const abi = JSON.parse(await readFile(new URL('./vault-abi.json', import.meta.url), 'utf8'));
const deployment = JSON.parse(await readFile(join(root, 'burrow_deployed.json'), 'utf8'));
const account = deployment.contracts.vault.deployment.deployer;
const E = 10n ** 18n;
const word = n => BigInt(n).toString(16).padStart(64, '0');
const hex = n => '0x' + word(n);
const array = a => encodeAbiParameters([{ type: 'uint256[]' }], [a]);
const topic = sig => keccak256(toHex(sig));
const scratch = join(root, 'test/scratch/interactions');
await mkdir(scratch, { recursive: true });
const results = [];
const server = previewServer(join(root, 'dist'));
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = 'http://127.0.0.1:' + server.address().port;
const url = origin + '/preview/';
const browser = await chromium.launch({ args: ['--no-sandbox'] });

async function test(name, fn) {
  try { await fn(); results.push({ name, passed: true }); console.log('PASS', name); }
  catch (error) { results.push({ name, passed: false, error: String(error.stack || error) }); console.error('FAIL', name, error.message); }
}

async function scenario({ wallet = true, mobile = false, failRpc = false, failFeed = false, wrongChain = false, rejectSwitch = false, rejectConnect = false, position = [], debt = 0n, historyFailure = false, selfStaked = false } = {}) {
  const context = await browser.newContext({ viewport: { width: mobile ? 390 : 1440, height: 844 },
    reducedMotion: 'reduce', colorScheme: 'light', ...(mobile ? { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148' } : {}) });
  const page = await context.newPage();
  const errors = [], missing = [], calls = [];
  const state = { failRpc, failFeed, historyFailure, position: [...position], debt, receipts: '0x1', transactions: [], allowance: 0n, approved: false, shares: 100n * E, sqk: 500n * E };
  page.on('pageerror', e => errors.push(e.message));
  page.on('response', r => { if (r.url().startsWith(origin) && r.status() >= 400) missing.push(r.url()); });
  await context.route('**/v1/**', route => {
    if (state.failFeed) return route.fulfill({ status: 503, body: 'offline test' });
    const p = new URL(route.request().url()), key = p.pathname.slice(4) + p.search;
    const data = structuredClone(fixture[key]);
    if (key === 'status') data.measurement.observedAt = new Date().toISOString();
    return route.fulfill({ json: data });
  });
  async function rpcRoute(route) {
    if (state.failRpc) return route.fulfill({ status: 503, body: 'offline test' });
    const request = route.request().postDataJSON(); calls.push(request);
    const { method, params } = request;
    let result;
    if (method === 'eth_blockNumber') result = '0x' + (BigInt(C.burrow.vaultBlock) + 30n).toString(16);
    else if (method === 'eth_getTransactionReceipt') result = { status: state.receipts };
    else if (method === 'eth_getLogs') {
      const filter = params[0];
      if (state.historyFailure) return route.fulfill({ json: { jsonrpc: '2.0', id: 1, error: { code: -32000, message: 'pruned history test' } } });
      if (filter.address.toLowerCase() === C.squeekchain.nft.toLowerCase()) {
        result = [{ topics: [topic('Transfer(address,address,uint256)'), hex(0), '0x' + account.slice(2).padStart(64, '0'), hex(1)] }];
      } else if (filter.topics[0] === topic('Opened(address,uint256)') && state.position.length) {
        result = [{ topics: [filter.topics[0], '0x' + account.slice(2).padStart(64, '0')], data: hex(100n * E) }];
      } else result = [];
    } else if (method === 'eth_call') {
      const { to, data } = params[0], selector = data.slice(0, 10);
      const values = {
        '0x01e1d114': 1000n * E, '0x18160ddd': 1000n * E, '0x3192164f': 900n * E,
        '0x47bd3718': 100n * E, '0xede75094': 0n, '0xdb3ad22c': state.position.length ? 100n * E : 0n,
        '0x8eff1a98': 2536783358n, '0x07a2d13a': E, '0x7a720b5f': E, '0x276b7377': 6000n,
        '0x81c6c976': 0n, '0x402914f5': 0n, '0x09a343d5': state.position.length ? 100n * E : 0n,
        '0xd283e75f': state.debt, '0xc2d4507a': state.position.length ? 60n * E : 0n,
        '0x68b500eb': state.position.length ? 75n * E : 0n, '0x05c58df2': 1n,
        '0x60ee7643': 100n, '0xdd62ed3e': state.allowance, '0xe985e9c5': state.approved ? 1n : 0n,
      };
      if (selector === '0x22c38aed') result = array(state.position);
      else if (selector === '0x70a08231') result = hex(to.toLowerCase() === C.burrow.vault.toLowerCase() ? state.shares : state.sqk);
      else if (['0x301bd28e', '0x8ada6b0f'].includes(selector)) result = '0x' + C.squeekchain.nft.slice(2).padStart(64, '0');
      else if (selector === '0x5752a646') result = hex(1);
      else if (selector === '0x6352211e') result = '0x' + (state.position.length ? C.burrow.vault : selfStaked ? C.squeekchain.staking : account).slice(2).padStart(64, '0');
      else if (selector === '0x5e020ebb') result = '0x' + account.slice(2).padStart(64, '0');
      else if (selector === '0x4e026d42') result = encodeAbiParameters([{ type: 'string' }], ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><circle cx="10" cy="10" r="8" fill="#d9a441"/></svg>']);
      else if (selector in values) result = hex(values[selector]);
      else throw new Error('Unmocked contract selector: ' + selector);
    } else throw new Error('Unmocked RPC method: ' + method);
    return route.fulfill({ json: { jsonrpc: '2.0', id: request.id, result } });
  }
  for (const rpc of C.rpcs) await context.route(rpc + '/**', rpcRoute);
  // Public RPC URLs may serialize without a trailing slash in different engines.
  for (const rpc of C.rpcs) await context.route(rpc, rpcRoute);
  if (wallet) {
    await page.exposeFunction('__testSend', async tx => {
      state.transactions.push(tx);
      if (tx.data.startsWith('0x095ea7b3')) state.allowance = (1n << 256n) - 1n;
      else if (tx.data.startsWith('0xa22cb465')) state.approved = true;
      else if (state.receipts === '0x1') {
        const decoded = decodeFunctionData({ abi, data: tx.data });
        if (decoded.functionName === 'openPosition') state.position = [...decoded.args[0]];
        if (decoded.functionName === 'borrow') state.debt += decoded.args[0];
        if (decoded.functionName === 'repay') state.debt = state.debt > decoded.args[0] ? state.debt - decoded.args[0] : 0n;
        if (decoded.functionName === 'closePosition') state.position = [];
      }
      return deployment.contracts.vault.deployment.transactionHash;
    });
    await page.addInitScript(({ account, wrongChain, rejectSwitch, rejectConnect, chainHex }) => {
      const events = new Map();
      const mock = { account, chain: wrongChain ? '0x1' : chainHex, calls: [], rejectSend: false, rejectSwitch,
        request: async args => {
          mock.calls.push(args);
          if (args.method === 'eth_requestAccounts' && rejectConnect) throw Object.assign(new Error('Rejected'), { code: 4001 });
          if (['eth_requestAccounts', 'eth_accounts'].includes(args.method)) return mock.account ? [mock.account] : [];
          if (args.method === 'eth_chainId') return mock.chain;
          if (args.method === 'wallet_switchEthereumChain') {
            if (mock.rejectSwitch) throw Object.assign(new Error('Declined network switch'), { code: 4001 });
            mock.chain = args.params[0].chainId; for (const f of events.get('chainChanged') || []) f(mock.chain); return null;
          }
          if (args.method === 'eth_sendTransaction') {
            if (mock.rejectSend) throw Object.assign(new Error('User rejected transaction'), { code: 4001 });
            return window.__testSend(args.params[0]);
          }
          throw new Error('Unexpected wallet request: ' + args.method);
        },
        on: (event, callback) => { const list = events.get(event) || []; list.push(callback); events.set(event, list); },
        removeListener: (event, callback) => events.set(event, (events.get(event) || []).filter(x => x !== callback)),
        emit: (event, value) => { for (const callback of events.get(event) || []) callback(value); },
      };
      window.__mock = mock;
      const announce = () => window.dispatchEvent(new CustomEvent('eip6963:announceProvider', { detail: { info: { uuid: 'test-provider', name: 'Test wallet', icon: 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28"%3E%3Ccircle cx="14" cy="14" r="12" fill="%239d6a0f"/%3E%3C/svg%3E' }, provider: mock } }));
      window.addEventListener('eip6963:requestProvider', announce);
    }, { account, wrongChain, rejectSwitch, rejectConnect, chainHex: C.chainHex });
  }
  await page.goto(url);
  await page.locator('#tick').filter({ hasText: failFeed ? 'feed offline' : 'synced' }).waitFor();
  return { page, state, calls, errors, missing, close: () => context.close(), connect: async () => {
    await page.locator('#connect').click(); await page.getByRole('button', { name: 'Test wallet', exact: true }).click();
    await page.waitForFunction(() => document.body.classList.contains('has-view'));
    await page.waitForFunction(() => !document.getElementById('look').disabled);
  } };
}

try {
  await test('Export has complete local assets and no absolute internal URLs', async () => {
    async function walk(dir) { return (await Promise.all((await readdir(dir, { withFileTypes: true })).map(f => f.isDirectory() ? walk(join(dir, f.name)) : join(dir, f.name)))).flat(); }
    const files = await walk(join(root, 'dist'));
    for (const file of files.filter(f => /\.html$/.test(f))) {
      const html = await readFile(file, 'utf8');
      for (const [, value] of html.matchAll(/(?:href|src|content)="([^"]+)"/g)) {
        if (!/^(?:\.\.?\/|assets\/|styles\.css|app\.js|config\.js|wheel\.js)/.test(value)) continue;
        const target = new URL(value, 'http://local/' + file.slice(join(root, 'dist').length + 1));
        await readFile(join(root, 'dist', decodeURIComponent(target.pathname)));
      }
      assert(!/(?:href|src)="\/(?!\/)/.test(html), file + ' has root-relative assets');
    }
    assert(!files.some(f => /node_modules|\.tgz$|package-lock|\.map$/.test(f)));
  });
  await test('First screen, relative subpath, and reflow at 320/390/768/1120/1440 in both themes', async () => {
    const s = await scenario({ wallet: false });
    for (const colorScheme of ['light', 'dark']) {
      await s.page.emulateMedia({ colorScheme });
      for (const width of [320, 390, 768, 1120, 1440]) {
        await s.page.setViewportSize({ width, height: 844 });
        const metrics = await s.page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, width: innerWidth, h1: document.querySelector('h1').getBoundingClientRect().bottom, action: document.querySelector('.hero-act .pri').getBoundingClientRect().bottom }));
        assert(metrics.scroll <= width, JSON.stringify(metrics));
        if (width === 390) { assert(metrics.h1 < 844); assert(metrics.action < 844); }
        await s.page.screenshot({ path: join(scratch, `${colorScheme}-${width}.png`) });
      }
    }
    assert.deepEqual(s.errors, []); assert.deepEqual(s.missing, []); await s.close();
  });
  await test('Main navigation and read-only account lookup by Enter', async () => {
    const s = await scenario({ wallet: false });
    await s.page.getByRole('link', { name: 'Open a position', exact: true }).click(); assert(s.page.url().endsWith('#position'));
    await s.page.getByRole('link', { name: 'Lend SQK', exact: true }).click(); assert(s.page.url().endsWith('#lend-panel'));
    await s.page.locator('#addr').fill(account); await s.page.locator('#addr').press('Enter');
    await s.page.waitForFunction(() => document.body.classList.contains('has-view') && !document.getElementById('look').disabled);
    assert(await s.page.locator('#deposit').isDisabled()); assert(await s.page.locator('#borrow').isDisabled());
    assert.equal(await s.page.locator('.nft').getAttribute('aria-disabled'), 'true');
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Invalid address has an announced inline error and sends no account request', async () => {
    const s = await scenario({ wallet: false });
    await s.page.locator('#addr').fill('not-an-address'); await s.page.locator('#look').click();
    assert.equal(await s.page.locator('#addr').getAttribute('aria-invalid'), 'true');
    assert.match(await s.page.locator('#accountStatus').innerText(), /40 hexadecimal/);
    assert(!s.calls.some(c => c.method === 'eth_call' && c.params[0].data.startsWith('0x22c38aed'))); await s.close();
  });
  await test('No-wallet chooser: keyboard trap, Escape, focus return, local Coinbase SDK', async () => {
    const s = await scenario({ wallet: false });
    await s.page.locator('#connect').focus(); await s.page.keyboard.press('Enter');
    assert(await s.page.locator('#walletDialog').isVisible());
    await s.page.keyboard.press('Tab'); await s.page.keyboard.press('Tab');
    assert(await s.page.evaluate(() => document.querySelector('#walletDialog').contains(document.activeElement)));
    await s.page.keyboard.press('Escape'); assert(await s.page.locator('#connect').evaluate(el => el === document.activeElement));
    assert(await s.page.evaluate(async () => typeof (await import('./vendor/coinbase.js')).createCoinbaseWalletSDK === 'function'));
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Phone chooser offers all four wallet deep links and Coinbase Smart Wallet', async () => {
    const s = await scenario({ wallet: false, mobile: true }); await s.page.locator('#connect').click();
    for (const name of ['MetaMask', 'Coinbase Wallet', 'Rabby', 'Phantom']) {
      const link = s.page.getByRole('link', { name: 'Open in ' + name, exact: true }); assert(await link.isVisible()); assert.match(await link.getAttribute('href'), /^https:\/\//);
    }
    assert(await s.page.getByRole('button', { name: 'Coinbase Smart Wallet', exact: true }).isVisible());
    await s.page.screenshot({ path: join(scratch, 'mobile-wallet.png') }); assert.deepEqual(s.missing, []); await s.close();
  });
  await test('EIP-6963 discovery, connect, full address and disconnect', async () => {
    const s = await scenario(); await s.connect(); assert.equal(await s.page.locator('#modeFlag').innerText(), 'connected');
    assert(await s.page.locator('#deposit').isEnabled());
    await s.page.locator('#connect').click(); assert.equal(await s.page.locator('.wallet-address').innerText(), account);
    await s.page.getByRole('button', { name: 'Disconnect', exact: true }).click();
    assert.equal(await s.page.locator('#connect').innerText(), 'Connect wallet'); assert(await s.page.locator('#deposit').isDisabled());
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Wallet rejection stays recoverable and announces the reason', async () => {
    const s = await scenario({ rejectConnect: true }); await s.page.locator('#connect').click(); await s.page.getByRole('button', { name: 'Test wallet', exact: true }).click();
    await s.page.getByText('Request declined. Choose a wallet to try again.').waitFor();
    assert(await s.page.getByRole('button', { name: 'Test wallet', exact: true }).isEnabled()); assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Wrong-network actions disabled; switch to Sepolia recovers', async () => {
    const s = await scenario({ wrongChain: true, rejectSwitch: true }); await s.connect();
    assert.equal(await s.page.locator('#modeFlag').innerText(), 'wrong network'); assert(await s.page.locator('#deposit').isDisabled());
    await s.page.evaluate(() => { window.__mock.rejectSwitch = false; });
    await s.page.getByRole('button', { name: 'Switch to Sepolia', exact: true }).last().click();
    await s.page.waitForFunction(() => document.getElementById('modeFlag').textContent === 'connected');
    assert(await s.page.locator('#deposit').isEnabled()); assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Decimal validation rejects negative, zero, exponent and >18 decimal amounts', async () => {
    const s = await scenario(); await s.connect();
    for (const value of ['-1', '0', '1e3', '0.0000000000000000001', 'letters']) {
      await s.page.locator('#lendAmt').fill(value); await s.page.locator('#deposit').click();
      assert.match(await s.page.locator('#lendStatus').innerText(), /positive SQK amount/);
    }
    assert.equal(s.state.transactions.length, 0); await s.close();
  });
  await test('Deposit approval, pending lock and confirmed calldata use the live vault', async () => {
    const s = await scenario(); await s.connect(); await s.page.locator('#lendAmt').fill('1.25'); await s.page.locator('#deposit').click();
    await s.page.waitForFunction(() => document.getElementById('lendStatus').textContent.includes('pending'));
    assert(await s.page.locator('#deposit').isDisabled()); assert(await s.page.locator('#withdraw').isDisabled());
    await s.page.waitForFunction(() => document.getElementById('lendStatus').textContent.includes('Deposit: confirmed'));
    assert.equal(s.state.transactions.length, 2); assert.equal(s.state.transactions[0].to, C.squeekchain.sqk);
    const tx = s.state.transactions[1]; assert.equal(tx.to, C.burrow.vault); assert.equal(tx.from, account);
    const decoded = decodeFunctionData({ abi, data: tx.data }); assert.equal(decoded.functionName, 'deposit'); assert.equal(decoded.args[0], 1250000000000000000n);
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Wallet rejection and on-chain revert are distinct recoverable states', async () => {
    const s = await scenario(); await s.connect(); await s.page.locator('#lendAmt').fill('1');
    await s.page.evaluate(() => { window.__mock.rejectSend = true; }); await s.page.locator('#deposit').click();
    await s.page.getByText('Approve SQK: User rejected transaction', { exact: true }).waitFor(); assert(await s.page.locator('#deposit').isEnabled());
    await s.page.evaluate(() => { window.__mock.rejectSend = false; }); s.state.receipts = '0x0'; await s.page.locator('#deposit').click();
    await s.page.waitForFunction(() => document.getElementById('lendStatus').textContent.includes('reverted'));
    assert.equal(s.state.transactions.length, 1); assert.deepEqual(s.errors, []); await s.close();
  });
  await test('NFT keyboard selection and escrow call encode the selected token IDs', async () => {
    const s = await scenario(); await s.connect(); const nft = s.page.locator('.nft'); await nft.focus(); await s.page.keyboard.press('Space');
    assert.equal(await nft.getAttribute('aria-pressed'), 'true'); assert(await s.page.locator('#open').isEnabled());
    await s.page.locator('#open').click(); await s.page.waitForFunction(() => document.getElementById('status').textContent.includes('Escrow 1 NFT: confirmed'));
    const tx = s.state.transactions.at(-1), decoded = decodeFunctionData({ abi, data: tx.data });
    assert.equal(decoded.functionName, 'openPosition'); assert.deepEqual(decoded.args[0], [1n]); assert.equal(tx.to, C.burrow.vault);
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Self-staked NFTs are shown only after checking the actual depositor', async () => {
    const s = await scenario({ selfStaked: true }); await s.connect();
    assert.match(await s.page.locator('#invRows').innerText(), /staking \(self\)/);
    assert.equal(await s.page.locator('.nft').getAttribute('aria-disabled'), 'true');
    assert(s.calls.some(c => c.method === 'eth_call' && c.params[0].to === C.squeekchain.staking && c.params[0].data.startsWith('0x5e020ebb')));
    assert(await s.page.locator('#open').isDisabled()); assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Borrow, repay-all and close follow the position state', async () => {
    const s = await scenario({ position: [1n] }); await s.connect();
    await s.page.locator('#amount').fill('61'); await s.page.locator('#borrow').click(); assert.match(await s.page.locator('#status').innerText(), /exceeds.*credit line/);
    await s.page.locator('#amount').fill('2'); await s.page.locator('#borrow').click(); await s.page.waitForFunction(() => document.getElementById('status').textContent.includes('Borrow: confirmed'));
    await s.page.waitForFunction(() => !document.getElementById('repay').disabled); assert(await s.page.locator('#close').isDisabled());
    await s.page.locator('#amount').fill(''); await s.page.locator('#repay').click(); await s.page.waitForFunction(() => document.getElementById('status').textContent.includes('Repay: confirmed'));
    const repay = s.state.transactions.find(t => t.data.startsWith('0x371fd8e6')); assert.equal(decodeFunctionData({ abi, data: repay.data }).args[0], (1n << 256n) - 1n);
    await s.page.waitForFunction(() => !document.getElementById('close').disabled); await s.page.locator('#close').click();
    await s.page.waitForFunction(() => document.getElementById('status').textContent.includes('Close position: confirmed')); assert.deepEqual(s.state.position, []);
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('Withdraw never silently clamps an amount above the balance', async () => {
    const s = await scenario(); await s.connect(); await s.page.locator('#lendAmt').fill('101'); await s.page.locator('#withdraw').click();
    assert.match(await s.page.locator('#lendStatus').innerText(), /exceeds your bSQK balance/); assert.equal(s.state.transactions.length, 0);
    await s.page.locator('#lendAmt').fill('2'); await s.page.locator('#withdraw').click(); await s.page.waitForFunction(() => document.getElementById('lendStatus').textContent.includes('Withdraw: confirmed'));
    assert.equal(decodeFunctionData({ abi, data: s.state.transactions[0].data }).args[0], 2n * E); await s.close();
  });
  await test('Failed event history is never reported as no open positions', async () => {
    const s = await scenario({ historyFailure: true }); await s.page.getByText('Event history unavailable. Reload to retry.').first().waitFor();
    assert(!((await s.page.locator('#liq').innerText()).includes('No open positions'))); await s.close();
  });
  await test('Offline chain/feed errors do not fabricate balances and keep Connect usable', async () => {
    const s = await scenario({ failRpc: true, failFeed: true, wallet: false });
    await s.page.locator('#lend').filter({ hasText: 'Chain unavailable' }).waitFor(); assert.equal(await s.page.locator('#tick').innerText(), 'feed offline');
    await s.page.locator('#connect').click(); assert(await s.page.locator('#walletDialog').isVisible());
    await s.page.keyboard.press('Escape'); await s.page.locator('#addr').fill(account); await s.page.locator('#look').click();
    await s.page.getByText('Account could not be loaded. Check your connection and choose Load to retry.').waitFor();
    assert.deepEqual(s.errors, []); await s.close();
  });
  await test('A feed failure after success stays offline instead of reverting to synced', async () => {
    const s = await scenario({ wallet: false }); s.state.failFeed = true;
    await s.page.locator('#tick').filter({ hasText: 'feed offline' }).waitFor({ timeout: 16000 });
    await s.page.waitForTimeout(1200); assert.equal(await s.page.locator('#tick').innerText(), 'feed offline');
    assert.equal(await s.page.locator('#wheelCap span').innerText(), 'Feed offline'); await s.close();
  });
  await test('All deployed source links work without extensionless route rewrites', async () => {
    const s = await scenario({ wallet: false });
    const hrefs = await s.page.locator('#addrs a[href^="./source/"]').evaluateAll(links => links.map(a => a.href));
    for (const href of new Set(hrefs)) { const response = await s.page.goto(href); assert.equal(response.status(), 200); assert.match(await s.page.title(), /Burrow source/); }
    assert.deepEqual(s.missing, []); await s.close();
  });
  let webkitResult;
  try { const b = await webkit.launch(); await b.close(); webkitResult = 'Available'; }
  catch (e) { webkitResult = 'Not run: WebKit launch failed because required host libraries are unavailable. ' + e.message.slice(0, 350); }
  await writeFile(join(scratch, 'results.json'), JSON.stringify({ results, webkit: webkitResult }, null, 2));
  console.log(`${results.filter(r => r.passed).length}/${results.length} interaction checks passed. ${webkitResult}`);
  if (results.some(r => !r.passed)) process.exitCode = 1;
} finally {
  await browser.close(); await new Promise(r => server.close(r));
}
