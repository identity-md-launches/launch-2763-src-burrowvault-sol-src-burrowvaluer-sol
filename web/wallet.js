// Vanilla EIP-1193 / EIP-6963 connector, keeping the reference's single connect control.
import { CONFIG as C } from './config.js';

/** @typedef {import('./types').Provider} Provider */
/** @type {Map<string, {info: {name: string, icon: string}, provider: Provider}>} */
const discovered = new Map();
const dialog = /** @type {HTMLDialogElement} */ (document.getElementById('walletDialog'));
const rows = document.getElementById('walletRows');
const status = document.getElementById('walletStatus');
const title = document.getElementById('walletTitle');
const button = document.getElementById('connect');
const short = a => a.slice(0, 6) + '…' + a.slice(-4);
/** @type {Provider | null} */
let provider = null;
let account = '', chain = '', busy = false;
let opener = button;
/** @type {(account: string | null, chainOk: boolean) => void} */
let change = () => {};
const mobile = () => /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) && !window.ethereum && !discovered.size;
const chainOk = () => chain.toLowerCase() === C.chainHex;

export const walletProvider = () => provider;

function notify() {
  button.textContent = account ? (chainOk() ? short(account) : 'Switch to Sepolia') : 'Connect wallet';
  button.title = account || 'Connect a wallet';
  change(account || null, chainOk());
}
function errorText(error) {
  return error?.code === 4001 ? 'Request declined. Choose a wallet to try again.' :
    error?.code === -32002 ? 'A wallet request is already open. Check your wallet.' :
    (error?.message || 'Unable to connect. Check your wallet and try again.').split('\n')[0].slice(0, 180);
}
function row(label, icon, action) {
  const el = document.createElement('button'); el.type = 'button'; el.className = 'btn wallet-row';
  if (icon && /^(data:image\/|\.\/assets\/)/.test(icon)) {
    const img = document.createElement('img'); img.src = icon; img.alt = ''; img.width = 28; img.height = 28; el.append(img);
  }
  const text = document.createElement('span'); text.textContent = label; el.append(text);
  el.addEventListener('click', async () => {
    if (busy) return;
    busy = true; status.textContent = 'Opening ' + label + '…';
    rows.querySelectorAll('button').forEach(b => b.disabled = true);
    try { await action(); } catch (e) { status.textContent = errorText(e); }
    finally { busy = false; rows.querySelectorAll('button').forEach(b => b.disabled = false); }
  });
  rows.append(el);
}
async function switchChain() {
  try { await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: C.chainHex }] }); }
  catch (error) {
    if (error.code !== 4902) throw error;
    await provider.request({ method: 'wallet_addEthereumChain', params: [{
      chainId: C.chainHex, chainName: 'Ethereum Sepolia',
      nativeCurrency: { name: 'Sepolia Ether', symbol: 'ETH', decimals: 18 },
      rpcUrls: C.rpcs, blockExplorerUrls: [C.explorer],
    }] });
    await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: C.chainHex }] });
  }
  chain = String(await provider.request({ method: 'eth_chainId' })); notify();
}
const onAccounts = accounts => {
  account = Array.isArray(accounts) && /^0x[\da-f]{40}$/i.test(accounts[0]) ? accounts[0] : '';
  notify(); if (dialog.open) render();
};
const onChain = id => { chain = String(id); notify(); if (dialog.open) render(); };
const onDisconnect = () => { disconnect(); };
function detach() {
  provider?.removeListener?.('accountsChanged', onAccounts);
  provider?.removeListener?.('chainChanged', onChain);
  provider?.removeListener?.('disconnect', onDisconnect);
}
function disconnect() {
  const previous = provider;
  detach(); provider = null; account = ''; chain = ''; notify();
  // SDK sessions may disconnect; extension permissions stay under the user's control.
  previous?.disconnect?.().catch(() => {});
  dialog.close();
}
async function connect(next) {
  const accounts = await next.request({ method: 'eth_requestAccounts' });
  if (!Array.isArray(accounts) || !/^0x[\da-f]{40}$/i.test(accounts[0])) throw new Error('Wallet returned no account. Unlock it and try again.');
  const nextChain = String(await next.request({ method: 'eth_chainId' }));
  detach(); provider = next; account = accounts[0]; chain = nextChain;
  provider.on?.('accountsChanged', onAccounts); provider.on?.('chainChanged', onChain); provider.on?.('disconnect', onDisconnect);
  notify();
  if (!chainOk()) {
    try { await switchChain(); }
    catch (e) { render(); status.textContent = 'Connected on another network. Choose Switch to Sepolia to enable transactions.'; return; }
  }
  status.textContent = ''; dialog.close();
}
function render() {
  rows.replaceChildren(); status.textContent = ''; title.textContent = account ? 'Wallet' : 'Connect a wallet';
  if (account) {
    const addr = document.createElement('p'); addr.className = 'wallet-address'; addr.textContent = account; rows.append(addr);
    if (!chainOk()) row('Switch to Sepolia', './assets/favicon.svg', async () => { await switchChain(); render(); });
    row('Disconnect', './assets/wallet.svg', disconnect); return;
  }
  if (mobile()) {
    const url = location.href;
    const links = [
      ['MetaMask', './assets/metaMask.svg', 'https://metamask.app.link/dapp/' + url.replace(/^https?:\/\//, '')],
      ['Coinbase Wallet', './assets/coinbase.svg', 'https://go.cb-w.com/dapp?cb_url=' + encodeURIComponent(url)],
      ['Rabby', './assets/rabby.svg', 'https://go.rabby.io/mobile/dapp?url=' + encodeURIComponent(url)],
      ['Phantom', './assets/phantom.svg', 'https://phantom.app/ul/browse/' + encodeURIComponent(url) + '?ref=' + encodeURIComponent(location.origin)],
    ];
    for (const [name, icon, href] of links) {
      const a = document.createElement('a'); a.className = 'btn wallet-row'; a.href = href;
      const img = document.createElement('img'); img.src = icon; img.alt = ''; img.width = 28; img.height = 28;
      a.append(img, document.createTextNode('Open in ' + name)); rows.append(a);
    }
  }
  for (const { info, provider: p } of discovered.values()) row(info.name, info.icon, () => connect(p));
  if (!discovered.size && window.ethereum) row('Browser wallet', './assets/wallet.svg', () => connect(window.ethereum));
  if (!mobile() && !discovered.size && !window.ethereum) {
    const hint = document.createElement('p'); hint.className = 'hint'; hint.textContent = 'No browser wallet found. Open this page in a wallet browser or use Coinbase Smart Wallet.'; rows.append(hint);
  }
  row(mobile() ? 'Coinbase Smart Wallet' : 'Coinbase Wallet', './assets/coinbase.svg', async () => {
    const { createCoinbaseWalletSDK } = await import('./vendor/coinbase.js');
    const sdk = createCoinbaseWalletSDK({ appName: 'Burrow', appLogoUrl: new URL('./assets/favicon.svg', location.href).href,
      appChainIds: [C.chainId], preference: { options: 'smartWalletOnly' } });
    await connect(sdk.getProvider());
  });
}
export function openWallet() {
  opener = /** @type {HTMLElement} */ (document.activeElement);
  render(); if (!dialog.open) dialog.showModal();
}
/** @param {(account: string | null, chainOk: boolean) => void} onChange */
export function setupWallet(onChange) {
  change = onChange;
  button.addEventListener('click', openWallet);
  document.querySelectorAll('.js-connect').forEach(b => b.addEventListener('click', openWallet));
}
document.getElementById('walletClose').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  const r = dialog.getBoundingClientRect();
  if (event.target === dialog && (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom)) dialog.close();
});
dialog.addEventListener('close', () => opener?.focus());
dialog.addEventListener('keydown', event => {
  if (event.key !== 'Tab') return;
  const controls = [...dialog.querySelectorAll('button:not(:disabled),a[href]')];
  const first = /** @type {HTMLElement} */ (controls[0]);
  const last = /** @type {HTMLElement} */ (controls.at(-1));
  if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
  else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
});
window.addEventListener('eip6963:announceProvider', event => {
  const { info, provider: p } = /** @type {CustomEvent} */ (event).detail || {};
  if (!info || typeof info.uuid !== 'string' || typeof info.name !== 'string' || typeof p?.request !== 'function') return;
  const isNew = !discovered.has(info.uuid);
  discovered.set(info.uuid, { info, provider: p });
  if (isNew && dialog.open && !busy) render();
});
window.dispatchEvent(new Event('eip6963:requestProvider'));
