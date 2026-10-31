# Burrow

SQK lending against Squeek NFTs on Sepolia. A borrower escrows Squeek NFTs, the vault
re-stakes them on Squeekchain and names itself claim recipient, so the mining rewards of the
collateral pay the loan down by themselves. Lenders hold bSQK, an ERC-4626-style share whose
price rises with loan interest, marketplace fees and a Uniswap v4 swap hook.

Unaudited, testnet only. SQK has no value.

## Contracts (Sepolia)

| Contract | Role | Bytes |
| --- | --- | --- |
| `BurrowValuer` | Credit line = Σ staking.basePower(level) × governed price per power × 60% LTV. Price moves ≤20% per step behind a 48 h timelock; two-step ownership | 3.3 KB |
| `BurrowVaultLite` | bSQK vault: deposit / withdraw, openPosition / borrow / repay / closePosition, sweepRewards, liquidate. No owner, no admin | 9.8 KB |
| `BurrowMarket` | Fixed-price and Dutch-auction NFT sales, fee ≤5% donated to the vault | 6.5 KB |
| `BurrowHook` | v4 afterSwap + afterSwapReturnDelta hook, skims ≤1% of SQK output into the vault. Address must carry flag bits `0x44`, so it is CREATE2-mined through `HookFactory` | 5.2 KB |

Addresses are in the UI (Contracts panel) and in `burrow_deployed.json` next to this repo.

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

## Build and test

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

`deploy_v2.mjs` (ethers) deploys Valuer → Vault → Market, then mines a CREATE2 salt whose
address carries `0x44` in the low 14 bits and deploys the hook through `HookFactory`. Gas is set
by hand because the public RPC under-estimates a CREATE2 that runs out of gas and returns
address zero.

## Known limitations

* Fee donations raise the share price in one step; a just-in-time deposit can capture a slice
  of a large sale fee. Streaming donations over time would need more bytecode than the chain
  allows for this contract.
* Exact-output swaps through the hook pay no fee; v4 only lets an afterSwap delta touch the
  unspecified currency.
* Valuation is power-based. There is no NFT price feed on this chain, so price per power is a
  governed parameter rather than an oracle.
