import { CONFIG as C } from './config.js';
import { setupWallet, walletProvider } from './wallet.js';
/** @returns {HTMLElement & {value: string, disabled: boolean}} */
const $ = id => /** @type {HTMLElement & {value: string, disabled: boolean}} */ (document.getElementById(id));
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const B = C.burrow, Q = C.squeekchain;
const SEL = {
  deposit:'0xe2bbb158', withdraw:'0x441a3e70', openPosition:'0x95254d09', borrow:'0xc5ebeaec', repay:'0x371fd8e6',
  closePosition:'0xc393d0e3', sweepRewards:'0xc1e4d034', liquidate:'0x2f865568',
  debtOf:'0xd283e75f', creditLineOf:'0xc2d4507a', liquidationThresholdOf:'0x68b500eb', positionIds:'0x22c38aed',
  positionPower:'0x09a343d5', totalAssets:'0x01e1d114', totalSupply:'0x18160ddd', idle:'0x3192164f',
  balanceOf:'0x70a08231', convertToAssets:'0x07a2d13a', unsettled:'0xede75094', totalPower:'0xdb3ad22c',
  totalBorrows:'0x47bd3718', allowance:'0xdd62ed3e', approve:'0x095ea7b3', setApprovalForAll:'0xa22cb465',
  isApprovedForAll:'0xe985e9c5', pricePerPower:'0x7a720b5f', ltvBps:'0x276b7377', lastPriceChange:'0x81c6c976',
  powerForLevel:'0x60ee7643', level:'0x05c58df2', ownerOf:'0x6352211e', claimable:'0x402914f5', ratePerSecond:'0x8eff1a98',
  tokenURI:'0xc87b56dd',
  depositor:'0x5e020ebb', art:'0x301bd28e', seed:'0x5752a646', renderer:'0x8ada6b0f', renderSVG:'0x4e026d42',
};
const TOPIC = {
  locked:'0xd5987d72b516fb12b1d31e6a7ab75f0c975e512aba9225ebbbb1b58c25cbb7a7',
  opened:'0xc4b27f09c64550fd678a5b3c3a00f454814732e346e0f1c79d0add8f980346de',
  donated:'0x2a01595cddf097c90216094025db714da3f4e5bd8877b56ba86a24ecead8e543',
  swept:'0x8ca6abf6b1c0bd37b098133cb9c8a94eb36b3f0f859bbca87c56b032880f5b35',
  transfer:'0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
};
const E = 10n ** 18n, MAX = (1n << 256n) - 1n;
const pad = h => h.replace(/^0x/, '').toLowerCase().padStart(64, '0');
const word = n => BigInt(n).toString(16).padStart(64, '0');
const u = h => BigInt(h && h !== '0x' ? h : '0x0');
const addrOf = h => '0x' + h.slice(-40);
const short = a => a ? a.slice(0, 6) + '…' + a.slice(-4) : '—';
const num = (x, d = 2) => Number(x).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
const sqk = (bi, d = 2) => num(Number(bi) / 1e18, d);
const int = n => Number(n).toLocaleString('en-US');
function parseAmt(s) { s = String(s).trim().replace(/,/g, ''); if (!/^\d*(\.\d{0,18})?$/.test(s) || s === '' || s === '.') return null; const [i, f = ''] = s.split('.'); const value = BigInt(i || '0') * E + BigInt((f + '0'.repeat(18)).slice(0, 18)); return value <= MAX ? value : null; }

// --- JSON-RPC with fallback ---
let rpcI = 0, rpcTimer = null, rpcQ = [];
function rpc(method, params) {
  return new Promise((resolve, reject) => {
    rpcQ.push({ method, params, resolve, reject });
    if (!rpcTimer) rpcTimer = setTimeout(rpcFlush, 0);
  });
}
async function rpcFlush() {
  const queue = rpcQ; rpcQ = []; rpcTimer = null;
  for (let offset = 0; offset < queue.length; offset += 10) await rpcSend(queue.slice(offset, offset + 10));
}
async function rpcSend(batch) {
  let pending = batch.map((item, id) => ({ ...item, id })), error;
  const start = rpcI;
  for (let attempt = 0; attempt < C.rpcs.length && pending.length; attempt++) {
    const index = (start + attempt) % C.rpcs.length, url = C.rpcs[index];
    const body = JSON.stringify(pending.map(item => ({ jsonrpc: '2.0', id: item.id, method: item.method, params: item.params })));
    try {
      const response = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, signal: AbortSignal.timeout(15000), body });
      if (!response.ok) throw new Error('RPC HTTP ' + response.status);
      const json = await response.json(), replies = Array.isArray(json) ? json : [json];
      const byId = new Map(replies.map(reply => [reply.id, reply]));
      if (replies.length !== pending.length || byId.size !== pending.length || pending.some(item => !byId.has(item.id))) throw new Error('Incomplete RPC batch');
      pending = pending.filter(item => {
        const reply = byId.get(item.id);
        if (reply.error || !('result' in reply)) { error = new Error(reply.error?.message || 'RPC returned no result'); return true; }
        item.resolve(reply.result); return false;
      });
      if (!pending.length) rpcI = index;
    } catch (e) { error = e; console.warn('rpc', url, String(e.message).slice(0, 160)); }
  }
  pending.forEach(item => item.reject(error));
}
const call = (to, data) => rpc('eth_call', [{ to, data }, 'latest']);
const callU = async (to, data) => u(await call(to, data));
const logs = f => rpc('eth_getLogs', [f]);
// Public RPCs cap eth_getLogs at 50,000 blocks; walk the range in chunks, newest first.
async function logsRange(f, from, to, maxChunks = 12) {
  const out = []; const step = 49999n; let n = 0;
  for (let hi = to; hi >= from && n < maxChunks; n++) {
    const lo = hi - step > from ? hi - step : from;
    try { out.push(...await logs({ ...f, fromBlock: '0x' + lo.toString(16), toBlock: '0x' + hi.toString(16) })); }
    catch { throw new Error('Event history unavailable. Try Load again.'); }
    if (lo === from) return out; hi = lo - 1n;
  }
  if (to >= from) throw new Error('Event history exceeds this RPC scan. A complete inventory is unavailable.');
  return out;
}
const decStr = h => { const x = h.replace(/^0x/, ''); const o = parseInt(x.slice(0, 64), 16) * 2, l = parseInt(x.slice(o, o + 64), 16); let s = ''; for (let i = 0; i < l * 2; i += 2) s += '%' + x.substr(o + 64 + i, 2); return decodeURIComponent(s); };
const decArr = h => { const x = h.replace(/^0x/, ''); const o = parseInt(x.slice(0, 64), 16) * 2, l = parseInt(x.slice(o, o + 64), 16); const a = []; for (let i = 0; i < l; i++) a.push(BigInt('0x' + x.slice(o + 64 + i * 64, o + 128 + i * 64))); return a; };

/** @type {import('./types').AppState} */
const S = { acct: null, chainOk: false, view: null, sel: new Set(), inv: [], pos: null, vault: {}, valuer: {}, lend: {}, art: null, seed: null, renderer: null, apr: 0, gen: 0, dur: 600, observedAt: 0, rpm: 0 };

// --- reads ---
async function readVault() {
  const V = B.vault, X = B.valuer;
  const [assets, supply, idle, borrows, unsettled, power, rate, px, price, ltv, lastChange, claimable] = await Promise.all([
    callU(V, SEL.totalAssets), callU(V, SEL.totalSupply), callU(V, SEL.idle), callU(V, SEL.totalBorrows), callU(V, SEL.unsettled),
    callU(V, SEL.totalPower), callU(V, SEL.ratePerSecond), callU(V, SEL.convertToAssets + word(E)),
    callU(X, SEL.pricePerPower), callU(X, SEL.ltvBps), callU(X, SEL.lastPriceChange), callU(Q.staking, SEL.claimable + pad(V)),
  ]);
  S.vault = { assets, supply, idle, borrows, unsettled, power, rate, px, claimable };
  S.valuer = { price, ltv, lastChange };
  S.apr = Number(rate * 31536000n) / 1e18;
  const facts = document.querySelectorAll('.facts dd');
  facts[0].textContent = Number(ltv) / 100 + '%';
  facts[1].textContent = num(S.apr * 100, 0) + '%';
  facts[3].textContent = sqk(price, price % E ? 4 : 0) + ' SQK';
  $('lend').innerHTML = [
    ['Supplied', sqk(assets) + ' SQK'], ['Lent to borrowers', sqk(borrows) + ' SQK'], ['Utilisation', assets > 0n ? num(Number(borrows * 10000n / assets) / 100) + '%' : '0.00%'],
    ['Borrow APR', num(S.apr * 100) + '%'], ['Idle, withdrawable now', sqk(idle) + ' SQK'],
    ['Mined, awaiting settlement', sqk(unsettled) + ' SQK'], ['bSQK supply', sqk(supply)], ['1 bSQK', sqk(px, 4) + ' SQK'],
    ...(S.lend.shares != null && S.acct && S.acct.toLowerCase() === S.view?.toLowerCase() ? [['Your bSQK', sqk(S.lend.shares, 4)], ['Worth', sqk(S.lend.shares * px / E) + ' SQK'], ['Your SQK', sqk(S.lend.sqk) + ' SQK']] : []),
  ].map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('');
  const frozenUntil = Number(lastChange) + 3600, frozen = lastChange > 0n && Date.now() / 1000 < frozenUntil;
  $('params').innerHTML = [
    ['Loan-to-value', Number(ltv) / 100 + '%'], ['Liquidation threshold', '75% of value'], ['Liquidation bonus', '10%'],
    ['Borrow APR', num(S.apr * 100) + '%'], ['Price per power', sqk(price, 4) + ' SQK'], ['Price change', '≤20% per step, 48 h delay'],
    ['Liquidation freeze', frozen ? `until ${new Date(frozenUntil * 1000).toLocaleTimeString()}` : 'not frozen'],
    ['Collateral cap', '32 NFTs per position'], ['Valuation', 'staking basePower × price'],
  ].map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join('');
}

async function readRevenue() {
  try {
    const latest = u(await rpc('eth_blockNumber', []));
    const from = latest > 7200n ? latest - 7200n : 0n;
    const [don, sw] = await Promise.all([
      logs({ address: B.vault, topics: [TOPIC.donated], fromBlock: '0x' + from.toString(16), toBlock: 'latest' }),
      logs({ address: B.vault, topics: [TOPIC.swept], fromBlock: '0x' + from.toString(16), toBlock: 'latest' }),
    ]);
    const sum = (arr, pick) => arr.filter(pick).reduce((a, l) => a + u(l.data.slice(0, 66)), 0n);
    const isM = l => addrOf(l.topics[1]).toLowerCase() === B.market.toLowerCase();
    const isH = l => addrOf(l.topics[1]).toLowerCase() === B.hook.toLowerCase();
    const interest = S.vault.borrows * BigInt(Math.round(S.apr * 1e6)) / 1000000n / 365n;
    $('rev').innerHTML = [
      ['Loan interest (est.)', num(S.apr * 100) + '% APR', '50%', sqk(interest)],
      ['Mining rewards swept', 'per round', '—', sqk(sum(sw, () => true))],
      ['Marketplace fee', '2.50%', '5.00%', sqk(sum(don, isM))],
      ['v4 swap hook', '0.30%', '1.00%', sqk(sum(don, isH))],
    ].map(r => `<tr><td>${r[0]}</td><td class="n dim">${r[1]}</td><td class="n muted">${r[2]}</td><td class="n">${r[3]}</td></tr>`).join('');
  } catch { $('rev').innerHTML = '<tr><td colspan="4" class="muted">Event history unavailable. Reload to retry.</td></tr>'; }
}

async function readPositions() {
  try {
    const latest = u(await rpc('eth_blockNumber', []));
    const ev = await logsRange({ address: B.vault, topics: [TOPIC.opened] }, BigInt(B.vaultBlock), latest);
    const who = [...new Set(ev.map(l => addrOf(l.topics[1]).toLowerCase()))];
    const rows = await Promise.all(who.map(async a => {
      const [ids, debt, thr] = await Promise.all([call(B.vault, SEL.positionIds + pad(a)).then(decArr), callU(B.vault, SEL.debtOf + pad(a)), callU(B.vault, SEL.liquidationThresholdOf + pad(a))]);
      return { a, ids, debt, thr };
    }));
    const open = rows.filter(r => r.ids.length);
    if (!open.length) { $('liq').innerHTML = '<tr><td colspan="6" class="muted">No open positions</td></tr>'; return; }
    $('liq').innerHTML = open.map(r => {
      const hf = r.debt > 0n ? Number(r.thr * 100n / r.debt) / 100 : Infinity;
      const cls = hf < 1 ? 'neg' : hf < 1.2 ? 'warnc' : 'pos';
      const can = S.acct && S.chainOk && !busy && r.debt > r.thr && !liquidationFrozen();
      return `<tr><td class="n"><a href="${C.explorer}/address/${r.a}" title="${r.a}" aria-label="Borrower ${r.a}">${short(r.a)}</a></td><td class="n">${r.ids.length}</td><td class="n">${sqk(r.debt)}</td><td class="n">${sqk(r.thr)}</td><td class="n ${cls}">${hf === Infinity ? '∞' : hf.toFixed(2)}</td><td class="n"><button class="btn sm" data-liq="${r.a}" data-eligible="${r.debt > r.thr}" ${can ? '' : 'disabled'}>Liquidate</button></td></tr>`;
    }).join('');
    document.querySelectorAll('button[data-liq]').forEach(b => b.addEventListener('click', () => runAction('status', () => liquidate(/** @type {HTMLButtonElement} */ (b).dataset.liq))));
  } catch { $('liq').innerHTML = '<tr><td colspan="6" class="muted">Event history unavailable. Reload to retry.</td></tr>'; }
}

async function readAccount(a) {
  const version = ++accountRead;
  S.view = a; S.pos = null; S.lend = {}; S.sel.clear(); clearAccountFigures(); resetWheelAccount(); updateActions();
  readWheelAccount(a, version);
  $('accountStatus').textContent = 'Reading account…'; $('look').disabled = true;
  $('posFor').textContent = short(a);
  if (!S.valuer.ltv) await readVault();
  const V = B.vault;
  const [ids, power, debt, line, thr, shares, sqkBal, allow, approvedAll] = await Promise.all([
    call(V, SEL.positionIds + pad(a)).then(decArr), callU(V, SEL.positionPower + pad(a)), callU(V, SEL.debtOf + pad(a)),
    callU(V, SEL.creditLineOf + pad(a)), callU(V, SEL.liquidationThresholdOf + pad(a)), callU(V, SEL.balanceOf + pad(a)),
    callU(Q.sqk, SEL.balanceOf + pad(a)), callU(Q.sqk, SEL.allowance + pad(a) + pad(V)), callU(Q.nft, SEL.isApprovedForAll + pad(a) + pad(V)),
  ]);
  if (version !== accountRead) return;
  S.pos = { ids, power, debt, line, thr };
  S.lend = { shares, sqk: sqkBal, allow, approvedAll: approvedAll === 1n };
  await readVault();
  if (version !== accountRead) return;
  document.body.classList.add('has-view');
  $('posFor').title = a;
  const pend = S.vault.power > 0n ? S.vault.claimable * power / S.vault.power : 0n;
  $('pPower').textContent = int(Number(power / E));
  $('pPowerN').textContent = ids.length + (ids.length === 1 ? ' NFT escrowed' : ' NFTs escrowed');
  $('pLine').textContent = sqk(line);
  $('pDebt').textContent = sqk(debt);
  $('pThr').textContent = sqk(thr);
  $('pPend').textContent = sqk(pend);
  const hf = debt > 0n ? Number(thr * 100n / debt) / 100 : Infinity;
  $('pHf').innerHTML = debt > 0n ? `<span class="${hf < 1 ? 'neg' : hf < 1.2 ? 'warnc' : 'pos'}">${hf.toFixed(2)}</span>` : '<span class="muted">∞</span>';
  drawGauge(debt, line, thr);
  const mine = S.acct && S.acct.toLowerCase() === a.toLowerCase();
  updateActions();
  $('posHint').textContent = ids.length ? `Escrowed #${ids.join(', #')}` : mine ? 'Select wallet NFTs below, then escrow them' : '';
  if (version !== accountRead) return;
  await loadInventory(a, ids, version);
  if (version !== accountRead) return;
  $('accountStatus').textContent = ''; $('look').disabled = false;
  readPositions();
}

function drawGauge(debt, line, thr) {
  const value = line > 0n ? line * 10000n / S.valuer.ltv : 0n;
  const f = x => value > 0n ? Math.min(1, Number(x * 1000n / value) / 1000) : 0;
  const arc = (t, r = 70) => { const a = Math.PI * (1 - t); return [84 + r * Math.cos(a), 92 - r * Math.sin(a)]; };
  const path = (t0, t1, r = 70) => { const [x0, y0] = arc(t0, r), [x1, y1] = arc(t1, r); return `M${x0.toFixed(1)} ${y0.toFixed(1)}A${r} ${r} 0 ${t1 - t0 > .5 ? 1 : 0} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`; };
  const d = f(debt), l = f(line), t = f(thr);
  const col = debt === 0n ? 'var(--ink3)' : d > t ? 'var(--neg)' : d > l ? 'var(--warn)' : 'var(--acc)';
  const tick = (x, label) => { const [a, b] = arc(x, 80), [c, e] = arc(x, 62); return `<line x1="${a.toFixed(1)}" y1="${b.toFixed(1)}" x2="${c.toFixed(1)}" y2="${e.toFixed(1)}" stroke="var(--ink3)" stroke-width="1"/><text x="${arc(x, 94)[0].toFixed(1)}" y="${arc(x, 94)[1].toFixed(1)}" font-size="10" fill="var(--ink3)" text-anchor="middle" font-family="var(--mono)">${label}</text>`; };
  $('gauge').innerHTML = `<path d="${path(0, 1)}" stroke="var(--line2)" stroke-width="10" fill="none" stroke-linecap="butt"/>` +
    (d > 0 ? `<path d="${path(0, d)}" stroke="${col}" stroke-width="10" fill="none"/>` : '') +
    (value > 0n ? tick(l, '60%') + tick(t, '75%') : '') +
    `<text x="84" y="84" text-anchor="middle" font-size="14" font-family="var(--mono)" fill="var(--ink)">${value > 0n ? (d * 100).toFixed(1) + '%' : '—'}</text>`;
  $('gaugeLbl').textContent = value > 0n ? `of ${sqk(value, 0)} SQK collateral value` : 'no collateral';
}

const powerCache = new Map();
const powerFor = lv => { const k = String(lv); if (!powerCache.has(k)) powerCache.set(k, callU(B.valuer, SEL.powerForLevel + word(lv)).catch(e => { powerCache.delete(k); throw e; })); return powerCache.get(k); };
async function loadInventory(a, escrowed, version) {
  $('invHint').textContent = 'reading';
  let ids = new Set(escrowed.map(String));
  let inventoryWarning = '';
  try {
    const latest = u(await rpc('eth_blockNumber', []));
    const ev = await logsRange({ address: Q.nft, topics: [TOPIC.transfer, null, '0x' + pad(a)] }, BigInt(Q.nftBlock), latest);
    for (const l of ev) ids.add(u(l.topics[3]).toString());
  } catch { inventoryWarning = 'Wallet history unavailable; only escrowed NFTs are shown. Load to retry.'; }
  const list = [...ids].map(Number).sort((x, y) => x - y);
  const rows = await Promise.all(list.map(async id => {
    const [owner, lv] = await Promise.all([call(Q.nft, SEL.ownerOf + word(id)).then(addrOf).catch(() => null), callU(Q.nft, SEL.level + word(id)).catch(() => null)]);
    if (!owner) return null;
    if (lv === null) { inventoryWarning = 'Some NFT levels are unavailable. Load to retry.'; return null; }
    const o = owner.toLowerCase();
    let custody = escrowed.map(String).includes(String(id)) ? 'Burrow (staked)' : o === a.toLowerCase() ? 'wallet' : null;
    if (!custody && o === Q.staking.toLowerCase()) {
      const depositor = addrOf(await call(Q.staking, SEL.depositor + pad(Q.nft) + word(id)));
      if (depositor.toLowerCase() === a.toLowerCase()) custody = 'staking (self)';
    }
    if (!custody) return null;
    const power = await powerFor(lv);
    return { id, lv: Number(lv), power, custody, free: custody === 'wallet' };
  }));
  if (version !== accountRead) return;
  S.inv = rows.filter(Boolean);
  const mine = S.acct && S.acct.toLowerCase() === a.toLowerCase();
  $('invHint').textContent = inventoryWarning || (S.inv.length ? `${S.inv.length} Squeek NFT${S.inv.length === 1 ? '' : 's'}` : 'no Squeek NFTs for this account');
  const price = S.valuer.price || 0n, ltv = S.valuer.ltv || 6000n;
  $('inv').innerHTML = S.inv.map(n => `<button type="button" class="nft" aria-label="Squeek NFT ${n.id}, level ${n.lv}, ${n.custody}" aria-disabled="${!(n.free && mine)}" aria-pressed="${S.sel.has(String(n.id))}" data-id="${n.id}" data-locked="${n.free && mine ? 0 : 1}"><span class="a" data-a="${n.id}"></span><span class="f"><span>#${n.id}</span><span>L${n.lv}</span></span></button>`).join('');
  $('invRows').innerHTML = S.inv.map(n => `<tr><td class="n">#${n.id}</td><td class="n">${n.lv}</td><td class="n">${int(n.power)}</td><td class="n">${sqk(n.power * price * ltv / 10000n)}</td><td class="dim">${n.custody}</td></tr>`).join('');
  for (const n of S.inv) art(n.id, document.querySelector(`[data-a="${n.id}"]`));
  if (!S.inv.length) preview(inventoryWarning || 'No Squeek NFTs for this account · collection preview');
  document.querySelectorAll('button.nft').forEach(el => el.addEventListener('click', () => {
    const target = /** @type {HTMLButtonElement} */ (el);
    if (target.dataset.locked === '1' || busy || !S.chainOk) return;
    const id = target.dataset.id;
    if (S.sel.has(id)) S.sel.delete(id); else { if (S.sel.size >= 32) { $('status').textContent = 'Select up to 32 NFTs per position.'; return; } S.sel.add(id); }
    el.setAttribute('aria-pressed', String(S.sel.has(id)));
    updateActions();
    $('posHint').textContent = S.sel.size ? `Escrow #${[...S.sel].map(Number).sort((x, y) => x - y).join(', #')}` : 'Select wallet NFTs below, then escrow them';
  }));
}

function preview(hint = 'Collection preview · on-chain art') {
  const ids = [1, 222, 1111, 3333, 5555, 8888];
  $('invHint').textContent = hint;
  $('inv').innerHTML = ids.map(id => `<div class="nft" data-locked="1" data-preview aria-label="Preview of Squeek ${id}"><div class="a" data-a="${id}"></div><div class="f"><span>#${id}</span></div></div>`).join('');
  for (const id of ids) art(id, document.querySelector(`[data-a="${id}"]`));
}
async function art(id, el) {
  try {
    const uri = decStr(await call(Q.nft, SEL.tokenURI + word(id)));
    if (!uri.startsWith('data:application/json')) throw new Error('Unsupported token metadata');
    const body = uri.slice(uri.indexOf(',') + 1);
    const metadata = JSON.parse(uri.includes(';base64,') ? new TextDecoder().decode(Uint8Array.from(atob(body), c => c.charCodeAt(0))) : decodeURIComponent(body));
    if (!/^data:image\/(svg\+xml|png|webp|jpeg)[;,]/i.test(metadata.image)) throw new Error('Unsupported on-chain image');
    const image = new Image(); image.alt = metadata.name || `Squeek ${id}`;
    image.onload = () => { if (el.isConnected) window.nft3d?.(el, image); };
    image.src = metadata.image;
    el.replaceChildren(image);
  } catch { if (el.isConnected) el.textContent = 'Art unavailable'; }
}

// --- Wheel-native contracts: reads, account state and transactions ---
const H = B.hmtr, W = B.wheelBond, G = B.garage;
const HS = { mint:'0x1b2ef1ca', redeem:'0x7cbc2373', stake:'0xa694fc3a', unstake:'0x2e17de78', sharePrice:'0x87269729', nav:'0xc1590cd7', pouch:'0xa6148493', marketOpen:'0xc66bc046', stakedShares:'0x90a577ef', stakedOf:'0xaf500ba3', unitsOf:'0x0eccc708', unstakeAt:'0x922b3db4' };
const BS = { lock:'0x1338736f', redeem:'0xdb006a75', exit:'0x9dcedb6e', bonds:'0x5f1c17c0', bonusOf:'0xfb3d3df2', work:'0x322e9f04', nextId:'0x61b8ce8c' };
const GS = { park:'0x07afe492', claim:'0x5f581fe6', leave:'0x67dfd4c9', spots:'0x145a8bdf', value:'0xcadf338f', ready:'0xcd067e12', nextSpot:'0xced17c13', nextCar:'0x5221d2dd', parked:'0x273162a392a067f617f00058584ed513241844b90c4e7efb5705338e706b7fc7' };
const kv = rows => rows.map(([key, value]) => `<dt>${escapeHTML(key)}</dt><dd>${escapeHTML(value)}</dd>`).join('');
function resetWheelAccount() {
  S.hmReady = false; S.bondReady = false; S.garageReady = false;
  S.hmUnits = 0n; S.hmBalance = 0n; S.hmUnstakeAt = 0n;
  $('hmMine').textContent = 'Connect a wallet to mint with bSQK, redeem or stake HMTR';
  $('bondList').hidden = true; $('bondRows').replaceChildren();
  $('gList').hidden = true; $('gRows').replaceChildren();
}
function updateWheelActions() {
  const mine = !busy && S.chainOk && S.acct && S.acct.toLowerCase() === S.view?.toLowerCase();
  $('hmMint').disabled = !(mine && S.hmReady && S.hmPrice > 0n);
  $('hmRedeem').disabled = $('hmStake').disabled = !(mine && S.hmReady && S.hmBalance > 0n);
  $('hmUnstake').disabled = !(mine && S.hmReady && S.hmUnits > 0n && S.work != null && (S.work === 0n || S.work >= S.hmUnstakeAt));
  $('bondLock').disabled = !(mine && S.bondReady && S.work != null);
  $('gPark').disabled = !(mine && S.garageReady && S.hmReady);
  document.querySelectorAll('#bondRows button,#gRows button').forEach(el => {
    const button = /** @type {HTMLButtonElement} */ (el);
    button.disabled = !mine || !(button.closest('#bondRows') ? S.bondReady : S.garageReady) || button.dataset.blocked === 'true';
  });
}
async function readHmtr() {
  const [price, nav, supply, pouch, open, staked] = await Promise.all([callU(H, HS.sharePrice), callU(H, HS.nav), callU(H, SEL.totalSupply), callU(H, HS.pouch), callU(H, HS.marketOpen), callU(H, HS.stakedShares)]);
  S.hmPrice = price;
  $('hmStats').innerHTML = kv([['Market', open ? 'open' : 'closed'], ['Exit fee', open ? '1%' : '5%'], ['NAV per share', sqk(price, 4) + ' bSQK'], ['Backing', sqk(nav) + ' bSQK'], ['Shares issued', sqk(supply) + ' HMTR'], ['Staked back', sqk(staked) + ' HMTR'], ['Cheek pouch', sqk(pouch) + ' bSQK'], ['Fee split', '50% stakers, 25% price, 25% cheeks'], ['Cheeks empty', 'every 500 work']]);
  updateActions();
}
async function readBondStats() {
  const [locked, work, next] = await Promise.all([callU(B.vault, SEL.balanceOf + pad(W)), callU(W, BS.work), callU(W, BS.nextId)]);
  S.work = work;
  $('bondStats').innerHTML = kv([['Locked', sqk(locked) + ' bSQK'], ['Wheel clock', int(work) + ' work'], ['Bonds issued', int(next - 1n)], ['Early exit', 'up to 20%, falling to 0']]);
  updateActions();
}
async function readGarage() {
  const [spots, cars, parked] = await Promise.all([callU(G, GS.nextSpot), callU(G, GS.nextCar), callU(H, HS.stakedOf + pad(G))]);
  $('gStats').innerHTML = kv([['Parked', sqk(parked) + ' HMTR'], ['Spots taken', int(spots - 1n)], ['Cars delivered', int(cars - 1n)], ['Hold', '30 days']]);
}
async function refreshWheel() {
  await Promise.allSettled([
    readHmtr().catch(() => { S.hmPrice = null; $('hmStats').innerHTML = kv([['Hamster Motors', 'Chain unavailable. Retrying automatically.']]); updateActions(); }),
    readBondStats().catch(() => { S.work = null; $('bondStats').innerHTML = kv([['Wheel bonds', 'Chain unavailable. Retrying automatically.']]); updateActions(); }),
    readGarage().catch(() => { $('gStats').innerHTML = kv([['Garage', 'Chain unavailable. Retrying automatically.']]); }),
  ]);
}
async function readHmtrAccount(account, version) {
  const [balance, staked, units, ready] = await Promise.all([callU(H, SEL.balanceOf + pad(account)), callU(H, HS.stakedOf + pad(account)), callU(H, HS.unitsOf + pad(account)), callU(H, HS.unstakeAt + pad(account))]);
  if (version !== accountRead) return;
  S.hmBalance = balance; S.hmUnits = units; S.hmUnstakeAt = ready; S.hmReady = true;
  $('hmMine').textContent = `${short(account)}: ${sqk(balance)} HMTR, ${sqk(staked)} staked${units ? `, unstake from ${int(ready)} work` : ''}`;
  updateActions();
}
async function readBonds(account, version) {
  const latest = u(await rpc('eth_blockNumber', []));
  const events = await logsRange({ address: W, topics: [TOPIC.locked, null, '0x' + pad(account)] }, BigInt(B.wheelBondBlock), latest);
  const ids = [...new Set(events.map(event => u(event.topics[1])))];
  const work = await callU(W, BS.work);
  const rows = (await Promise.all(ids.map(async id => {
    const [raw, bonus] = await Promise.all([call(W, BS.bonds + word(id)), callU(W, BS.bonusOf + word(id))]);
    const data = raw.slice(2), owner = addrOf('0x' + data.slice(0, 64)), start = u('0x' + data.slice(64, 128)), end = u('0x' + data.slice(128, 192)), shares = u('0x' + data.slice(192, 256));
    if (!shares || owner.toLowerCase() !== account.toLowerCase()) return null;
    const done = work >= end ? 1 : work <= start ? 0 : Number(work - start) / Number(end - start);
    return { id, shares, end, bonus, done };
  }))).filter(Boolean).sort((a, b) => Number(a.id - b.id));
  if (version !== accountRead) return;
  S.work = work; S.bondReady = true;
  $('bondList').hidden = !rows.length;
  const mine = S.acct?.toLowerCase() === account.toLowerCase();
  $('bondRows').innerHTML = rows.map(row => `<tr><td class="n">#${row.id}</td><td class="n">${sqk(row.shares)}</td><td><span class="bar" role="progressbar" aria-label="Bond ${row.id} wheel work" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(row.done * 100)}" title="Ends at ${int(row.end)} work"><i style="transform:scaleX(${row.done})"></i></span><span class="hint">${Math.round(row.done * 100)}%</span></td><td class="n">${sqk(row.bonus)}</td><td><span class="bact">${!mine ? '' : row.done >= 1 ? `<button class="btn sm" data-redeem="${row.id}">Redeem</button>` : `<button class="btn sm" data-exit="${row.id}" data-min="${row.shares * 7999n / 10000n}">Exit early</button>`}</span></td></tr>`).join('');
  updateActions();
}
async function readGarageAccount(account, version) {
  const latest = u(await rpc('eth_blockNumber', []));
  const [events, unlock, work] = await Promise.all([
    logsRange({ address: G, topics: [GS.parked, null, '0x' + pad(account)] }, BigInt(B.garageBlock), latest),
    callU(H, HS.unstakeAt + pad(G)), callU(W, BS.work),
  ]);
  const now = BigInt(Math.floor(Date.now() / 1000));
  const rows = (await Promise.all([...new Set(events.map(event => u(event.topics[1])))].map(async id => {
    const [raw, value, ready] = await Promise.all([call(G, GS.spots + word(id)), callU(G, GS.value + word(id)), callU(G, GS.ready + word(id))]);
    const data = raw.slice(2), owner = addrOf('0x' + data.slice(0, 64)), claimed = u('0x' + data.slice(128, 192)) !== 0n;
    if (owner.toLowerCase() !== account.toLowerCase()) return null;
    return { id, value, ready, claimed };
  }))).filter(Boolean);
  if (version !== accountRead) return;
  S.garageReady = true;
  $('gList').hidden = !rows.length;
  const mine = S.acct?.toLowerCase() === account.toLowerCase(), blocked = work !== 0n && work < unlock;
  $('gRows').innerHTML = rows.map(row => `<tr><td class="n">#${row.id}</td><td class="n">${sqk(row.value)}</td><td>${row.claimed ? 'delivered' : now >= row.ready ? 'ready' : num(Number(row.ready - now) / 86400, 1) + ' days'}</td><td><span class="bact">${!mine ? '' : `${now >= row.ready && !row.claimed ? `<button class="btn sm" data-claim="${row.id}">Claim car</button>` : ''}<button class="btn sm" data-leave="${row.id}" data-blocked="${blocked}" ${blocked ? 'disabled' : ''}>Leave</button>`}</span>${mine && blocked ? `<span class="hint">Unlocks at ${int(unlock)} work</span>` : ''}</td></tr>`).join('');
  updateActions();
}
async function readWheelAccount(account, version) {
  /** @type {[((account: string, version: number) => Promise<void>), string, string][]} */
  const tasks = [[readHmtrAccount, 'hmStatus', 'hmReady'], [readBonds, 'bondStatus', 'bondReady'], [readGarageAccount, 'gStatus', 'garageReady']];
  await Promise.allSettled(tasks.map(async ([read, status, flag]) => {
    try { await read(account, version); if (version === accountRead && $(status).textContent.startsWith('Account data unavailable.')) $(status).textContent = ''; }
    catch {
      if (version !== accountRead) return;
      S[flag] = false;
      $(status).textContent = 'Account data unavailable. Choose Load to retry; checking again automatically.';
      updateActions();
    }
  }));
}
function paceNote() {
  const text = $('bondTerm').value.trim(), term = /^\d+$/.test(text) ? Number(text) : 0;
  $('bondPace').textContent = term < 500 || term > 1000000 ? 'Term runs from 500 to 1,000,000 whole work units'
    : S.workDay > 0 ? `${int(term)} work is about ${num(term / S.workDay, 1)} days at the last 24 h pace; longer if the hamster naps.` : 'Term in settled wheel work; bonds rest when the wheel is idle.';
}
function fieldError(id, message) { $(id).setAttribute('aria-invalid', 'true'); $(id).focus(); return new Error(message); }
for (const id of ['hmAmt','gAmt','bondAmt','bondTerm']) $(id).addEventListener('input', () => $(id).removeAttribute('aria-invalid'));
const wheelAmount = (id, status, token) => {
  const value = parseAmt($(id).value);
  if (!value) { const message = `Enter a positive ${token} amount with at most 18 decimals.`; fieldError(id, message); $(status).textContent = message; return null; }
  $(id).removeAttribute('aria-invalid');
  return value;
};
async function approveFor(token, spender, amount, label, status) {
  const allowance = await callU(token, SEL.allowance + pad(S.acct) + pad(spender));
  return allowance >= amount || await tx(token, SEL.approve + pad(spender) + word(amount), label, status);
}
async function wheelTx(to, data, label, status) {
  if (await tx(to, data, label, status)) {
    await refreshWheel();
    if (S.acct === actionAccount) await loadAccount(S.acct);
  }
}
$('hmMint').addEventListener('click', () => runAction('hmStatus', async () => {
  const value = wheelAmount('hmAmt', 'hmStatus', 'bSQK'); if (!value) return;
  const [price, balance] = await Promise.all([callU(H, HS.sharePrice), callU(B.vault, SEL.balanceOf + pad(S.acct))]);
  if (value > balance) throw fieldError('hmAmt', 'Amount exceeds your bSQK balance.');
  if (!price) throw new Error('Share price unavailable. Choose Load to retry.');
  if (!await approveFor(B.vault, H, value, 'Approve bSQK', 'hmStatus')) return;
  await wheelTx(H, HS.mint + word(value) + word(value * E / price * 99n / 100n), 'Mint HMTR', 'hmStatus');
}));
$('hmRedeem').addEventListener('click', () => runAction('hmStatus', async () => {
  const value = wheelAmount('hmAmt', 'hmStatus', 'HMTR'); if (!value) return;
  const [price, balance] = await Promise.all([callU(H, HS.sharePrice), callU(H, SEL.balanceOf + pad(S.acct))]);
  if (value > balance) throw fieldError('hmAmt', 'Amount exceeds your HMTR balance.');
  await wheelTx(H, HS.redeem + word(value) + word(value * price / E * 94n / 100n), 'Redeem HMTR', 'hmStatus');
}));
$('hmStake').addEventListener('click', () => runAction('hmStatus', async () => {
  const value = wheelAmount('hmAmt', 'hmStatus', 'HMTR'); if (!value) return;
  if (value > S.hmBalance) throw fieldError('hmAmt', 'Amount exceeds your HMTR balance.');
  await wheelTx(H, HS.stake + word(value), 'Stake HMTR', 'hmStatus');
}));
$('hmUnstake').addEventListener('click', () => runAction('hmStatus', () => wheelTx(H, HS.unstake + word(S.hmUnits), 'Unstake HMTR', 'hmStatus')));
$('gPark').addEventListener('click', () => runAction('gStatus', async () => {
  const value = wheelAmount('gAmt', 'gStatus', 'HMTR'); if (!value) return;
  if (value < 100n * E) throw fieldError('gAmt', 'Park at least 100 HMTR.');
  if (value > S.hmBalance) throw fieldError('gAmt', 'Amount exceeds your HMTR balance.');
  if (!await approveFor(H, G, value, 'Approve HMTR', 'gStatus')) return;
  await wheelTx(G, GS.park + word(value), 'Park HMTR', 'gStatus');
}));
$('gRows').addEventListener('click', event => {
  const button = /** @type {HTMLElement} */ (event.target).closest('button'); if (!button || button.disabled) return;
  if (button.dataset.claim) runAction('gStatus', () => wheelTx(G, GS.claim + word(button.dataset.claim), 'Claim car', 'gStatus'));
  else runAction('gStatus', () => wheelTx(G, GS.leave + word(button.dataset.leave), 'Leave garage', 'gStatus'));
});
$('bondTerm').addEventListener('input', paceNote);
$('bondLock').addEventListener('click', () => runAction('bondStatus', async () => {
  const value = wheelAmount('bondAmt', 'bondStatus', 'bSQK'), text = $('bondTerm').value.trim(); if (!value) return;
  if (!/^\d+$/.test(text) || BigInt(text) < 500n || BigInt(text) > 1000000n) throw fieldError('bondTerm', 'Term runs from 500 to 1,000,000 whole work units.');
  if (value > (1n << 128n) - 1n) throw fieldError('bondAmt', 'Amount exceeds the bond contract limit.');
  const balance = await callU(B.vault, SEL.balanceOf + pad(S.acct));
  if (value > balance) throw fieldError('bondAmt', 'Amount exceeds your bSQK balance.');
  if (!await approveFor(B.vault, W, value, 'Approve bSQK', 'bondStatus')) return;
  await wheelTx(W, BS.lock + word(value) + word(BigInt(text)), 'Lock bond', 'bondStatus');
}));
$('bondRows').addEventListener('click', event => {
  const button = /** @type {HTMLElement} */ (event.target).closest('button'); if (!button || button.disabled) return;
  if (button.dataset.redeem) runAction('bondStatus', () => wheelTx(W, BS.redeem + word(button.dataset.redeem), 'Redeem bond #' + button.dataset.redeem, 'bondStatus'));
  else runAction('bondStatus', () => wheelTx(W, BS.exit + word(button.dataset.exit) + word(button.dataset.min), 'Exit bond #' + button.dataset.exit, 'bondStatus'));
});

// --- Squeekchain feed (hardware sample every 10 s) ---
const cache = {}, etags = {};
async function getCached(path) {
  const h = new Headers(); if (etags[path]) h.set('if-none-match', etags[path]);
  const r = await fetch(Q.api + '/' + path, { headers: h, signal: AbortSignal.timeout(12000) });
  if (r.status === 304) return cache[path];
  if (!r.ok) throw new Error(path + ' ' + r.status);
  const et = r.headers.get('etag'); if (et) etags[path] = et;
  const j = await r.json(); cache[path] = j; return j;
}
let lastSync = 0, feedOnline = false, feedStale = false, staleAfter = 120000;
async function live() {
  try {
    const [st, core, eco, se] = await Promise.all(['status', 'core', 'economy/state', 'settlements?range=24h'].map(getCached));
    S.observedAt = Date.parse(st.measurement.observedAt);
    if (!Number.isFinite(S.observedAt) || !Number.isFinite(Number(st.measurement.rpmMilli))) throw new Error('Invalid feed sample');
    S.gen = Number(core.configuration.genesisTimestamp); S.dur = Number(core.configuration.roundDuration);
    S.rpm = Math.max(0, Number(st.measurement.rpmMilli) / 1000);
    S.workDay = Number(se.summary.workAdded); paceNote();
    staleAfter = Number(st.measurement.staleAfterSeconds || 120) * 1000;
    feedStale = st.measurement.freshness !== 'online' || Date.now() - S.observedAt > staleAfter;
    window.__rpm = S.rpm; document.dispatchEvent(new CustomEvent('wheel-rpm', { detail: S.rpm }));   // drives the 3D wheel in wheel.js
    const w = $('wheel'); w.classList.toggle('on', S.rpm > 0); if (S.rpm > 0) w.style.animationDuration = (60 / S.rpm).toFixed(2) + 's';
    $('kWheel').innerHTML = feedStale ? '<span class="muted">unavailable</span>' : S.rpm > 0 ? `<span class="pos">${S.rpm.toFixed(1)} rpm</span>` : '<span class="muted">idle</span>';
    $('kBlock').textContent = int(core.core.blockHeight);
    $('kRoundNo').textContent = int(se.mining.processedThroughRound);
    $('kMint').textContent = (Number(BigInt(se.mining.rangeMintedBaseUnits)) / 1e18 / 1e6).toFixed(2) + 'M';
    $('kRpp').textContent = num(Number(BigInt(eco.staking.sqkPerPower)) / 1e18) + ' SQK';
    $('kPow').textContent = int(Math.round(Number(BigInt(eco.staking.totalNftPower)) / 1e18));
    const ep = eco.staking.exitPolicy;
    $('chain').innerHTML = [
      ['Work units', int(st.measurement.cumulativeWorkUnits), 'lifetime'],
      ['Distance, this counter epoch', (Number(st.measurement.distanceMm) / 1e6).toFixed(3) + ' km', st.measurement.counterEpoch ? 'resets when the counter restarts · ' + String(st.measurement.counterEpoch).slice(0, 8) : ''],
      ['Settlements, 24 h', int(se.summary.settlementCount), int(se.summary.completedBlockCount) + ' blocks'],
      ['SQK minted, total', (Number(BigInt(se.mining.miningMintedBaseUnits)) / 1e18 / 1e6).toFixed(2) + 'M', 'cap 2,100M'],
      ['SQK staked', int(Number(BigInt(eco.staking.totalStakedBaseUnits)) / 1e18), 'exit toll ' + ep.minBps / 100 + ' to ' + ep.maxBps / 100 + '%'],
    ].map(r => `<tr><td class="muted">${escapeHTML(r[0])}</td><td class="n">${escapeHTML(r[1])}</td><td class="n muted">${escapeHTML(r[2])}</td></tr>`).join('');
    lastSync = Date.now(); feedOnline = true;
    $('tick').textContent = feedStale ? 'feed stale' : 'synced 0 s ago';
    if (feedStale) { $('wheel').classList.remove('on'); document.dispatchEvent(new Event('wheel-offline')); }
  } catch {
    feedOnline = false; $('tick').textContent = 'feed offline';
    $('tick').title = lastSync ? 'Last successful sync: ' + new Date(lastSync).toLocaleString() : 'Retrying the Squeekchain feed automatically';
    $('wheel').classList.remove('on'); window.__rpm = 0; document.dispatchEvent(new Event('wheel-offline'));
    if (!lastSync) $('chain').innerHTML = '<tr><td class="muted">Feed unavailable. Retrying automatically.</td></tr>';
  }
}
function schedule() { const base = S.observedAt || Date.now(); let wait = 10000 - ((Date.now() - base) % 10000) + 400; if (wait < 800) wait += 10000; setTimeout(async () => { await live(); schedule(); }, wait); }
setInterval(() => {
  if (feedOnline && S.observedAt && Date.now() - S.observedAt > staleAfter) { feedStale = true; $('tick').textContent = 'feed stale'; $('wheel').classList.remove('on'); document.dispatchEvent(new Event('wheel-offline')); }
  if (lastSync && feedOnline && !feedStale) $('tick').textContent = 'synced ' + Math.round((Date.now() - lastSync) / 1000) + ' s ago';
  if (S.gen) { const now = Math.floor(Date.now() / 1000); const left = S.dur - (now - S.gen) % S.dur; $('kRound').textContent = Math.floor(left / 60) + 'm ' + String(left % 60).padStart(2, '0') + 's'; }
}, 1000);

// --- wallet and transactions ---
const eth = walletProvider;
let busy = false, accountRead = 0;
let actionAccount = null;
const liquidationFrozen = () => S.valuer.lastChange > 0n && Date.now() / 1000 < Number(S.valuer.lastChange) + 3600;
function clearAccountFigures() {
  document.body.classList.remove('has-view');
  for (const term of $('lend').querySelectorAll('dt')) {
    if (['Your bSQK', 'Worth', 'Your SQK'].includes(term.textContent)) { term.nextElementSibling?.remove(); term.remove(); }
  }
}
function updateActions() {
  const mine = !busy && S.chainOk && S.acct && S.acct.toLowerCase() === S.view?.toLowerCase() && S.pos;
  updateWheelActions();
  $('borrow').disabled = !(mine && S.pos.ids.length && S.pos.line > S.pos.debt);
  $('repay').disabled = !(mine && S.pos.debt > 0n);
  $('close').disabled = !(mine && S.pos.ids.length && S.pos.debt === 0n);
  $('open').disabled = !(mine && !S.pos.ids.length && S.sel.size);
  $('sweep').disabled = !(!busy && S.acct && S.chainOk);
  $('deposit').disabled = !mine;
  $('withdraw').disabled = !(mine && S.lend.shares > 0n);
  document.querySelectorAll('button[data-liq]').forEach(el => { const b = /** @type {HTMLButtonElement} */ (el); b.disabled = busy || !S.acct || !S.chainOk || liquidationFrozen() || b.dataset.eligible !== 'true'; });
}
async function loadAccount(a) {
  const attempt = accountRead + 1;
  try { await readAccount(a); }
  catch (e) {
    if (S.view !== a || attempt !== accountRead) return;
    S.pos = null; S.lend = {}; updateActions(); document.body.classList.remove('has-view');
    $('accountStatus').textContent = 'Account could not be loaded. Check your connection and choose Load to retry.';
    $('invHint').textContent = 'account unavailable'; $('look').disabled = false;
  }
}
async function runAction(statusEl, action) {
  if (busy) return;
  busy = true; actionAccount = S.acct; updateActions();
  try { await action(); }
  catch (e) { $(statusEl).textContent = (e.message || 'Unable to complete. Try again.').split('\n')[0].slice(0, 180); }
  finally { busy = false; actionAccount = null; updateActions(); }
}
setupWallet((account, chainOk) => {
  const changed = S.acct !== account;
  S.acct = account; S.chainOk = chainOk; S.sel.clear();
  document.body.classList.toggle('has-acct', !!account);
  $('modeFlag').textContent = account ? (chainOk ? 'connected' : 'wrong network') : 'read-only';
  $('modeFlag').className = 'flag ' + (account ? (chainOk ? 'on' : 'off') : '');
  $('lendFlag').textContent = account && chainOk ? 'connected' : 'read-only';
  $('lendFlag').className = 'flag ' + (account && chainOk ? 'on' : '');
  updateActions();
  if (account && (changed || !S.pos)) { $('addr').value = account; loadAccount(account); }
  if (!account) { resetWheelAccount(); preview(); ++accountRead; clearAccountFigures(); S.view = null; S.pos = null; S.lend = {}; $('look').disabled = false; $('addr').value = ''; $('accountStatus').textContent = ''; $('invHint').textContent = 'no account'; $('posFor').textContent = 'no account'; document.body.classList.remove('has-view'); }
  readPositions();
});
async function tx(to, data, label, statusEl = 'status') {
  const st = $(statusEl);
  if (!S.acct || !S.chainOk) { st.textContent = 'Connect a wallet on Sepolia first'; return false; }
  if (actionAccount !== S.acct) { st.textContent = 'Wallet account changed. Retry the action with the current account.'; return false; }
  st.textContent = label + ': confirm in wallet';
  let hash;
  try {
    const provider = eth();
    const [chain, accounts] = await Promise.all([provider.request({ method: 'eth_chainId' }), provider.request({ method: 'eth_accounts' })]);
    if (String(chain).toLowerCase() !== C.chainHex || !Array.isArray(accounts) || accounts[0]?.toLowerCase() !== S.acct.toLowerCase()) throw new Error('Wallet account or network changed. Reconnect before trying again.');
    hash = await provider.request({ method: 'eth_sendTransaction', params: [{ from: S.acct, to, data }] });
    if (typeof hash !== 'string' || !/^0x[0-9a-f]{64}$/i.test(hash)) throw new Error('Wallet returned an invalid transaction hash');
  }
  catch (e) { st.textContent = label + ': ' + (e.message || 'rejected').split('\n')[0].slice(0, 120); return false; }
  st.innerHTML = `${escapeHTML(label)}: pending <a href="${C.explorer}/tx/${hash}">${hash.slice(0, 10)}…</a>`;
  for (let i = 0; i < 60; i++) {
    await new Promise(r => setTimeout(r, 3000));
    const rc = await rpc('eth_getTransactionReceipt', [hash]).catch(() => null);
    if (rc) { const ok = rc.status === '0x1'; st.innerHTML = `${escapeHTML(label)}: ${ok ? 'confirmed' : '<span class="neg">reverted</span>'} <a href="${C.explorer}/tx/${hash}">${hash.slice(0, 10)}…</a>`; return ok; }
  }
  st.innerHTML = `${escapeHTML(label)}: still pending. Check <a href="${C.explorer}/tx/${hash}">the transaction</a> before retrying.`; return false;
}
async function ensureAllowance(amount, statusEl) {
  if (!S.acct || !S.chainOk || actionAccount !== S.acct) return false;
  const allowance = await callU(Q.sqk, SEL.allowance + pad(S.acct) + pad(B.vault));
  if (allowance >= amount) return true;
  const ok = await tx(Q.sqk, SEL.approve + pad(B.vault) + word(MAX), 'Approve SQK', statusEl);
  if (ok) S.lend.allow = MAX; return ok;
}
const amt = (id, st) => { const v = parseAmt($(id).value); if (v == null || v === 0n) { $(st).textContent = 'Enter a positive SQK amount with at most 18 decimals'; return null; } return v; };

$('deposit').addEventListener('click', () => runAction('lendStatus', async () => { const v = amt('lendAmt', 'lendStatus'); if (!v) return; if (v > S.lend.sqk) { $('lendStatus').textContent = 'Amount exceeds your SQK balance.'; return; } if (!await ensureAllowance(v, 'lendStatus')) return; if (await tx(B.vault, SEL.deposit + word(v) + word(0), 'Deposit', 'lendStatus')) await loadAccount(S.acct); }));
$('withdraw').addEventListener('click', () => runAction('lendStatus', async () => {
  const v = amt('lendAmt', 'lendStatus'); if (!v) return;
  if (!S.vault.px) { $('lendStatus').textContent = 'Share price unavailable. Load your account again.'; return; }
  let shares = v * E / S.vault.px; if (shares > S.lend.shares) { $('lendStatus').textContent = 'Amount exceeds your bSQK balance.'; return; }
  if (shares === 0n) { $('lendStatus').textContent = 'Amount is smaller than one share unit.'; return; }
  if (await tx(B.vault, SEL.withdraw + word(shares) + word(0), 'Withdraw', 'lendStatus')) await loadAccount(S.acct);
}));
$('open').addEventListener('click', () => runAction('status', async () => {
  const ids = [...S.sel].map(BigInt).sort((a, b) => (a < b ? -1 : 1)); if (!ids.length) return;
  if (!S.lend.approvedAll) { if (!await tx(Q.nft, SEL.setApprovalForAll + pad(B.vault) + word(1), 'Approve Squeek NFTs')) return; S.lend.approvedAll = true; }
  const data = SEL.openPosition + word(32) + word(ids.length) + ids.map(word).join('');
  if (await tx(B.vault, data, 'Escrow ' + ids.length + ' NFT' + (ids.length > 1 ? 's' : ''))) { S.sel.clear(); await loadAccount(S.acct); }
}));
$('borrow').addEventListener('click', () => runAction('status', async () => { const v = amt('amount', 'status'); if (!v) return; if (v > S.pos.line - S.pos.debt) { $('status').textContent = 'Amount exceeds the available credit line.'; return; } if (v > S.vault.idle) { $('status').textContent = 'Amount exceeds available vault liquidity.'; return; } if (await tx(B.vault, SEL.borrow + word(v), 'Borrow')) await loadAccount(S.acct); }));
$('repay').addEventListener('click', () => runAction('status', async () => {
  const raw = $('amount').value.trim(); const v = raw ? parseAmt(raw) : MAX; if (v == null || v === 0n) { $('status').textContent = 'Enter an SQK amount, or leave blank to repay all'; return; }
  const need = v === MAX ? S.pos.debt * 101n / 100n : v;
  if (!await ensureAllowance(need, 'status')) return;
  if (await tx(B.vault, SEL.repay + word(v), 'Repay')) await loadAccount(S.acct);
}));
$('close').addEventListener('click', () => runAction('status', async () => { if (await tx(B.vault, SEL.closePosition, 'Close position')) await loadAccount(S.acct); }));
$('sweep').addEventListener('click', () => runAction('status', async () => { if (await tx(B.vault, SEL.sweepRewards, 'Sweep rewards')) await loadAccount(S.view); }));
async function liquidate(who) {
  const value = (await callU(B.vault, SEL.creditLineOf + pad(who))) * 10000n / S.valuer.ltv;
  const pay = value * 9000n / 10000n;
  $('status').textContent = `Liquidate ${short(who)}: pay about ${sqk(pay)} SQK for its NFTs`;
  if (!await ensureAllowance(pay * 101n / 100n, 'status')) return;
  if (await tx(B.vault, SEL.liquidate + pad(who), 'Liquidate ' + short(who))) await loadAccount(S.acct);
}
$('look').addEventListener('click', () => {
  const a = $('addr').value.trim();
  if (!/^0x[0-9a-fA-F]{40}$/.test(a)) { $('addr').setAttribute('aria-invalid', 'true'); $('accountStatus').textContent = 'Enter an Ethereum address: 0x followed by 40 hexadecimal characters.'; return; }
  $('addr').removeAttribute('aria-invalid'); S.sel.clear(); loadAccount(a);
});
$('addr').addEventListener('keydown', e => { if (e.key === 'Enter') $('look').click(); });

// --- boot ---
const sf = a => `https://sourcify.dev/server/v2/contract/11155111/${a}?fields=all`;
$('addrs').innerHTML = [['Vault, bSQK', B.vault, 'BurrowVaultLite'], ['Valuer', B.valuer, 'BurrowValuer'], ['Market', B.market, 'BurrowMarket'], ['Wheel bonds', B.wheelBond, 'WheelBond'], ['Hamster Motors', B.hmtr, 'WheelStock'], ['Garage', B.garage, 'HamsterGarage'], ['v4 hook', B.hook, 'BurrowHook'], ['SQK', Q.sqk], ['Squeek NFT', Q.nft], ['Squeekchain staking', Q.staking]]
  .map(([k, v, src]) => `<tr><td class="muted">${k}</td><td class="n"><a href="${C.explorer}/address/${v}" title="${v}" aria-label="${k}: ${v}">${short(v)}</a></td><td class="n">${src ? `<a href="./source/${src}.html">source</a> · <a href="${sf(v)}">verified</a>` : ''}</td></tr>`).join('') +
  `<tr><td class="muted">All files</td><td class="n" colspan="2"><a href="./source/index.html">source/ · contracts, tests, README</a></td></tr>`;
preview();
refreshWheel(); paceNote();
setInterval(() => { if (!document.hidden && !busy) { refreshWheel(); if (S.view) readWheelAccount(S.view, accountRead); } }, 30000);
live().then(schedule);
readVault().then(() => { readRevenue(); readPositions(); })
  .catch(() => {
    $('lend').innerHTML = '<dt>Vault</dt><dd>Chain unavailable</dd>';
    $('params').innerHTML = '<dt>Parameters</dt><dd>Chain unavailable</dd>';
    $('rev').innerHTML = '<tr><td colspan="4" class="muted">Chain unavailable. Reload to retry.</td></tr>';
    $('liq').innerHTML = '<tr><td colspan="6" class="muted">Chain unavailable. Reload to retry.</td></tr>';
  });
