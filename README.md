# Burrow

SQK lending against Squeek NFTs on Sepolia. A borrower escrows Squeek NFTs, the vault
re-stakes them on Squeekchain and names itself claim recipient, so the mining rewards of the
collateral pay the loan down by themselves. Lenders hold bSQK, an ERC-4626-style share whose
price rises with loan interest, marketplace fees and a Uniswap v4 swap hook.

Unaudited, testnet only. SQK has no value.

## Contracts (Sepolia)

| Contract | Role | Runtime bytes |
| --- | --- | --- |
| `BurrowValuer` | Credit line = Σ staking.basePower(level) × governed price per power × 60% LTV. Price moves ≤20% per step behind a 48 h timelock; two-step ownership | 3,513 |
| `BurrowVaultLite` | bSQK vault: deposit / withdraw, openPosition / borrow / repay / closePosition, sweepRewards, liquidate. No owner, no admin | 10,111 |
| `BurrowMarket` | Fixed-price and Dutch-auction NFT sales, fee ≤5% donated to the vault | 6,438 |
| `BurrowHook` | v4 afterSwap + afterSwapReturnDelta hook, skims ≤1% of SQK output into the vault. Address must carry flag bits `0x44`, so it is CREATE2-mined through `HookFactory` | 5,187 |

The live v2 deployment is recorded in [`burrow_deployed.json`](burrow_deployed.json),
[`web/config.js`](web/config.js), and the site's Contracts panel.

| Contract | Sepolia address | Deployment gas used |
| --- | --- | ---: |
| Vault / bSQK | `0xB63AbAb9019fa0Db4A3Ab1824C5E5Fa7171f1472` | 16,205,233 |
| Valuer | `0x8F677a270fFd8769C01876216991c98561302C7b` | 5,894,112 |
| Market | `0xDF0b997E701AaB73e69417e1910a9a9D93F0De8d` | 10,516,014 |
| Hook | `0x9e0827db5831c49F9390707b467aA12A76E74044` | 8,588,909 |

Read-only verification on 2026-10-31 confirmed Sourcify exact creation/runtime matches,
byte-identical local protocol sources, nonempty deployed bytecode and successful receipts below
16,777,216 gas. The source hashes, deployment blocks and transaction hashes are in the manifest;
[`web/validation/deployment-verification.json`](web/validation/deployment-verification.json) records the checks.
No contracts were changed or deployed by the site task.

Sepolia currently charges about 1,550 gas per byte of deployed code against a 16,777,216 gas
cap per transaction (EIP-7825), so every contract has to stay under roughly 10.6 KB. The vault
is written for that budget.

## Accounting that is easy to get wrong

* **Swept rewards are not lender money until a borrower settles.** `sweepRewards()` claims
  from staking and credits `rewardPerPower`; the claimed SQK is held in `unsettled` and is
  excluded from `totalAssets()` and from idle liquidity until each position settles. Without
  this the share price jumps at every sweep and a lender could withdraw between sweep and
  settle.
* **Rewards are measured against `tracked`, not a before/after balance**, because
  `staking.claim(account)` is permissionless: anyone can push the vault's rewards in early.
  Any SQK that arrives outside the vault's own transfers is treated as a reward on the next
  sweep.
* **Rewards above a borrower's debt are paid back to the borrower**, not kept by lenders.
* **Opening a position sweeps first**, so a new position never shares rewards mined before
  it existed; settling sweeps first, so a closing or liquidated position keeps what it mined.
* **Position power is Squeekchain's own `accountPower` delta**, so reward splitting between
  borrowers matches the real reward stream.
* **Liquidation** opens when debt exceeds 75% of collateral value (borrowing stops at 60%).
  The liquidator takes every NFT and pays 90% of value; anything above the debt is returned
  to the borrower, any shortfall is written off against the share price so a sunk position
  can always be cleared. Liquidation is frozen for one hour after a price change.
* The first deposit locks `MINIMUM_LIQUIDITY` shares in the vault itself against share
  inflation; `donate()` only ever raises the share price.

## Contract build and test

```
forge build
forge test                                        # 70 unit, invariant and mutation-backed tests
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com forge test --match-test testFork
```

The fork tests run the vault against the real Squeekchain staking contract (escrow, re-stake,
borrow, repay, close, liquidate), the real Squeek NFT, a real NFT sale through the market and
a real swap through the Sepolia Uniswap v4 PoolManager with the hook attached.

`test/Fixtures.t.sol` declares Foundry's cheatcode ABI directly; `forge-std` is only needed by
`VaultLite.t.sol` and `ForkLite.t.sol`.

## Deploy

The operator deployed Valuer → Vault → Market, then mined a CREATE2 salt whose address
carries `0x44` in the low 14 bits and deployed the hook through `HookFactory`. The operator's
`deploy_v2.mjs` is not part of this checkout. The site uses the existing deployment; rebuilding
or previewing it never sends a transaction.

## Known limitations

* Fee donations raise the share price in one step; a just-in-time deposit can capture a slice
  of a large sale fee. Streaming donations over time would need more bytecode than the chain
  allows for this contract.
* Exact-output swaps through the hook pay no fee; v4 only lets an afterSwap delta touch the
  unspecified currency.
* Valuation is power-based. There is no NFT price feed on this chain, so price per power is a
  governed parameter rather than an oracle.

## Website

The site reproduces the operator's [reference UI](https://burrow-squeek.vercel.app): the same
Geist typography, graphite/brass palette, live metrics, hamster wheel, lending/position panels,
collateral inventory and contract links. It retains the original plain HTML/CSS/JavaScript stack.
The committed [`dist/`](dist/) is the complete static export. No server, secrets, runtime package
installation or compilation step is needed to host it. Asset and source links are relative and
work under a gateway subpath. No SPA rewrites are required.

Source is in [`web/`](web/): `index.html`, `styles.css`, `app.js`, `config.js`, `wheel.js`, and
`wallet.js`. Fonts, icons, the share image and the two browser libraries are local. `web/vendor/`
contains only the required browser JavaScript, not an npm registry or dependency tree.

### Preview and rebuild

From the repository root with Node.js 20 or newer:

```sh
node web/tools/build.mjs
node web/tools/preview.mjs
```

Open `http://localhost:4173/preview/`. Stop the preview with Ctrl-C. An optional numeric argument
to `preview.mjs` chooses another port. Any ordinary static server can also serve `dist/` directly.
The build is an offline copy/export command; it checks deployment addresses and source hashes
and generates explicit `source/*.html` pages from the repository. It does not transpile the app.
Run it after changing source or documentation, and include the finished `dist/` in the submission.

### Install development tools and validate

The website itself needs no install. For the pinned typechecker, browser tests and optional
vendor refresh, install from `web/package.json` and `web/package-lock.json`:

```sh
node web/tools/install.mjs
node web/tools/check.mjs
PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers node test/scratch/site-tooling/node_modules/playwright/cli.js install chromium
PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers node web/tools/test.mjs
node web/tools/verify-deployment.mjs
```

The installer keeps generated dependencies in `test/scratch/site-tooling/` and the npm cache in
the OS temporary directory. Only frontend manifests live in `web/`; existing contract configuration
and dependencies are untouched. Do not submit generated `node_modules`, browser downloads or caches.
The test tool owns and closes its own HTTP server and serves the export under `/preview/`.

`check.mjs` runs TypeScript `checkJs`/`noEmit` over the application JavaScript and configuration.
Interaction tests use an explicitly mocked EIP-1193 provider and RPC responses; **they never send
real transactions**. Their recorded feed fixture is test-only and never copied into `dist/`.
The verification command makes public read-only RPC/Sourcify requests and updates its evidence
file. It does not certify the contracts' security.

To regenerate the local Three.js 0.160.0 and Coinbase Wallet SDK 4.3.7 bundles after installing:

```sh
node web/tools/vendor.mjs
node web/tools/build.mjs
```

The lockfile pins their dependency graph. Fonts are the reference's Google Fonts Latin WOFF2
files; third-party licenses and wallet-icon attribution are in `web/licenses/` and the export.
[`DESIGN.md`](DESIGN.md) documents the implemented system. Actual commands, results, corrections,
screenshots and browser limitations are recorded in [`web/validation/validation.md`](web/validation/validation.md).

Recorded results (2026-10-31): production export and typecheck passed; 20/20 Chromium interaction
checks, 16/16 pinned design checks and 12/12 rendered contrast pairs passed. All four deployed
protocol sources matched Sourcify exactly. WebKit and real wallet signing remain unperformed.

### Live data and wallets

The feed is exactly `https://api.squeekchain.com/v1`: `status`, `core`, `economy/state` and
`settlements?range=24h`, refreshed on the reference's approximately ten-second cadence. Wheel
rotation follows the measured RPM. Chain reads use the two public Sepolia RPCs in `web/config.js`.
Loading/error/stale states remain visible when those services cannot answer. There is no demo data
fallback and nothing is stored as a fabricated live balance.

Connect opens one native dialog for EIP-6963 browser wallets, a legacy EIP-1193 fallback, phone
links for MetaMask/Coinbase Wallet/Rabby/Phantom, and Coinbase Smart Wallet. The plain-JavaScript
implementation follows the pinned connector behavior without introducing React/wagmi or a build
pipeline. Coinbase's SDK loads locally only when selected; its passkey service is external.
There is no WalletConnect relay, API key or project ID. Connected accounts can disconnect or switch
to Sepolia; actions stay disabled for another account or network. A fresh wallet account/network
check precedes each send. Account lookup is read-only and works without a wallet.

The reference's approval and transaction semantics are retained: SQK approval is unlimited;
NFT approval is collection-wide; deposit/withdraw minimum output is zero. The wallet confirms
these requests. The UI guards duplicate submissions and invalid decimal/over-balance amounts.
The displayed 24-hour interest figure is an estimate, while fees and swept rewards use events
from approximately 7,200 Sepolia blocks. Historical RPC scans are limited to 12 × 50,000 blocks;
failed or incomplete scans report an error. Staked inventory checks the current depositor.

Actual funded-wallet signing, passkey creation and native mobile-app handoff were not performed.
WebKit could not launch because host libraries were unavailable; Chromium browser checks were run.
This website task did not rerun the existing Solidity unit/fork suite. Nothing is published by the
build commands; the committed export is the hosting deliverable.
