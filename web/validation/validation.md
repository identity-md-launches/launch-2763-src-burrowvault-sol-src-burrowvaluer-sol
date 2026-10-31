# Burrow v2 website validation

Worker-run evidence, 2026-10-31. This is not independent certification or a contract audit.

The committed report/evidence directory is `web/validation/`. Identical named output copies
are supplied in `artifacts/`, which this workspace excludes from Git; no ignore files were changed.

## Scope and result

The operator's reference at `https://burrow-squeek.vercel.app` was retrieved and inspected in
Chromium at 390 and 1440px. Its actual `index.html`, `styles.css`, `app.js`, `config.js` and
`wheel.js` were used as the starting point. The repository's pre-existing Solidity sources/tests
were preserved. The deployed four contract sources were already byte-identical to Sourcify.

The site keeps the reference's composition, copy, wheel geometry, typography, light/dark
themes, density, panels, four Burrow addresses and four Squeekchain feed endpoints. Changes
are limited to local asset packaging, metadata/source export, connector reach, accessibility,
and concrete state/validation defects described below. It remains plain static JavaScript;
the production build copies assets and generates source-view pages, without compiling the app.

| Area | Result |
| --- | --- |
| Brief requirements | 7 met; 0 missing; 0 faked |
| Primary interactions | 20/20 automated Chromium checks pass |
| Product and main action at 390 | Yes; product headline and Open a position visible, action bottom ≈516px in an 844px viewport |
| Pinned taste@1 | 16/16 checks pass after corrections |
| Rendered contrast follow-up | 12/12 measured pairs meet 4.5:1 |
| Deployed protocol | 4/4 exact source matches; 32/32 checked selectors/event topics match; 4/4 successful receipts below the gas cap |
| Copy / share card | Original headline and explanation retained; real title, description, favicon, `og:title`, local 1200×630 `og:image` |

The visual idea is the operator's working hamster wheel paired with a quiet, dense lending
dashboard in warm graphite and brass.

## Brief coverage

| Requirement | Evidence |
| --- | --- |
| “a usable website … working primary interactions and responsive layouts” | `web/` source; mock-wallet interaction suite; Chromium rendering at 320/390/768/1120/1440 in both themes |
| “dist/index.html and its assets … alongside the source and lockfile” | Complete `dist/`, local runtime assets, `web/package.json` and `web/package-lock.json`; source/export kept together in the submission |
| “production build, typecheck and useful interaction validation” | Commands and actual outcomes below; all use the export under `/preview/` |
| “applies the pinned Better Interface guide … six domains” | All six core sections read, implementation/review coverage and concrete fixes below |
| “first screen at 390 … title, favicon, description, og:title and og:image” | `web/index.html:6`, local `web/assets/`, mobile screenshot and taste share/layout checks |
| “DESIGN.md … tokens, typography, components and responsive behavior” | Repository-root `DESIGN.md`, extracted from final source, including deliberate reference conventions |
| “README … install, preview and rebuild” | README Website section with dependency-free export/preview and pinned development tooling commands |

Hosting is outside this assignment. No publication, deployment, mint or real transaction was
performed. New frontend manifests are inside `web/`; existing build/dependency paths, `.git/`,
`.github/` and environment files were not edited. No ignore file was changed.

## Commands and actual results

All commands were run from the repository root unless noted. Tooling installation used
`npm install --prefix test/scratch/site-tooling --cache /tmp/burrow-npm-cache --no-audit --no-fund`
to create the pinned lockfile. The reusable `node web/tools/install.mjs` performs the equivalent
clean install with `npm ci`, using the committed manifest/lockfile and the same scratch directory.

| Command / check | Actual result |
| --- | --- |
| `node web/tools/build.mjs` | Exit 0. Complete offline static export, explicit `.html` source routes and relative assets. Rebuilt after the final source/README changes. |
| `node web/tools/check.mjs` | Exit 0. TypeScript 5.9.3 `checkJs`, `noEmit` on app/config/wallet/wheel, with typed state and provider interfaces; no `ts-nocheck`. |
| `PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers node web/tools/test.mjs` | Exit 0. 20/20 checks. Chromium 141.0.7390.37 via Playwright 1.56.1. The initial suite exposed a dialog focus failure; the repaired suite passed. |
| `node web/tools/verify-deployment.mjs` | Exit 0. 4 exact creation/runtime matches, identical local sources, 32 matching vault/valuer selectors/topics, and 4 successful low-gas deployment receipts. |
| `PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers IMD_PLAYWRIGHT="$PWD/test/scratch/site-tooling/node_modules/playwright/index.mjs" node .imd/reads/skills/design-critic/scripts/taste.mjs --out test/scratch/taste` | Exit 0. 16/16 checks on the final export. Initial result was 15/16 due to primary-button contrast. |
| Focused rendered-color script in `test/scratch/measure-styles.mjs` | 12/12 final pairs pass; the script reads real computed colors/backgrounds for controls, placeholders, hover rows, hints and inline errors in both themes. |
| Focused motion/ticker script in `test/scratch/motion-and-ticker.mjs` | At 1200px the final KPI is reachable by scrolling. Canvas screenshots remain identical under reduced motion, change with a simulated 60-RPM event, and become stable when the preference changes back to reduce. |
| `git diff --check` and path/size inspection | No whitespace errors; no package archives, dependency/cache trees, prohibited edits or submodules added. Source and required runtime assets retained under the 8 MiB budget. |

The pinned probe lives in assignment inputs and is removed after submission. Its extracted
check results are preserved in `taste.json`. The persistent interaction suite is
`web/tools/test.mjs`. One intermediate non-TTY test attempt was terminated (exit 143); it was
rerun in a foreground PTY and completed. WebKit installation downloaded a browser, but launch
failed due to missing host libraries including `libgtk-4`, `libpangocairo`, and `libgdk_pixbuf`.
No WebKit result is claimed.

The final two CSS-only refinements (placeholder contrast and intermediate-width ticker
scrolling) were checked by the final build/typecheck, rendered-color check, ticker check and
design probe; the passing 20-case application suite covers the unchanged application logic.

## Interaction coverage

`interactions.json` contains the full check names and results. The suite covers local asset
integrity; no root-relative internal links; mobile/desktop reflow in both themes; both hero
anchors; account lookup using Enter; invalid-address feedback without a read; read-only
disabling; no-wallet, phone, named EIP-6963 and rejected-wallet states; dialog Tab/Escape/focus
return; Coinbase module import; disconnect; rejected network switching and successful retry;
decimal/zero/negative/exponent validation; approval → deposit with pending-state locks;
transaction rejection versus revert; keyboard NFT selection → approval → escrow; verified
self-staking custody; borrow limit → borrow → repay all → close; excess withdrawal rejection
and correct share calldata; failed history; initial chain/feed failure; a feed becoming offline
after a successful sample; and every local deployed-source link.

Mocked transactions are decoded using the vault ABI retrieved from Sourcify, and their target
addresses/amounts are asserted. Fixtures are test-only, labelled as such in the test source, and
excluded from `dist/`. These are not on-chain transaction receipts. Live read-only RPC/API checks
were performed separately. Sweep/liquidate encoding and selectors were source-reviewed, but
those two write flows were not executed in a funded wallet or in the mock suite.

The live RPC observations were: vault 10,111 runtime bytes / 16,205,233 deployment gas; valuer
3,513 / 5,894,112; market 6,438 / 10,516,014; hook 5,187 / 8,588,909. Full public-source links,
hashes and checks are in `deployment-verification.json` and `burrow_deployed.json`.

## Better Interface: six-domain coverage

| Domain | Checked without a browser | Checked in the rendered export | Limits / not applicable |
| --- | --- | --- | --- |
| Accessibility | Native controls, landmark/heading structure, names, statuses, transaction gates, SVG isolation, reduced-motion branches | Keyboard lookup/selection/chooser, Tab loop, visible focus, Escape/restore, disabled states, measured minimum targets | No assistive-technology session; no physical keyboard/mobile device. Persistent visible form labels remain the reference's compact treatment, supplemented by accessible names. |
| Layout | Original grid/gutters/order, responsive rules, local scroll wrappers and source routing | 320/390/768/1120/1440 in both themes; first phone screen inspected; 1200 ticker reachability; no page overflow in tests/probe | Native 200% browser zoom/text resizing not performed. RTL/localization not implemented. |
| Writing | Original six-word product headline, explanatory sentence, verb actions, truthful empty/loading/error/status copy | Invalid address, no wallet, rejected request, wrong chain, pending/confirmed/reverted and failed data states | Fee window remains approximate; interest is explicitly marked estimated. No new marketing copy added. |
| Typography | Local Geist/Geist Mono, 400/500, measures, tabular figures, original scale and responsive input size | Both font faces confirmed loaded; phone/desktop wrapping; 5 repeated / 7 total sizes per entry viewport | No independent font-axis parser was available. The reference's 20px empty title and display size are intentional one-offs. |
| Colors | Semantic token roles and both original theme ramps retained, failing values adjusted | 16/16 probe plus 12 explicit solid-background contrast pairs; primary rest/hover, inline error, muted row hover, input placeholder and hint | Canvas/gradient/translucent art contrast not exhaustively measurable. Disabled controls are not represented as conforming active controls. |
| UI details | Original panel borders/radii, button states, limited transitions, entrance timing and wheel geometry | Reference/export screenshots, wallet sheet, hover/focus, actual wheel movement and preference changes | Coinbase passkey completion and native phone handoff unavailable without user interaction/accounts. WebGL-loss fallback inspected in source, not forced in the browser. |

No theme, font, section or transaction feature was added just to satisfy the guide. The explicit
“Reproduce that UI one to one … do not redesign it” governs the original density, repeated
Connect controls, entrance motion, `.98` press scale, heading arrangement and numeric styling.
The probe reports 18 controls below its comfortable 44px preference; all measured controls meet
its 24px-or-spacing requirement. This preserves the operator's compact controls rather than
turning the page into another layout.

## Findings, corrections and rechecks

| Severity / domain | Source location and original behavior | Correction and evidence |
| --- | --- | --- |
| High / Colors | `web/styles.css:22`, `.btn.pri`: reference white-on-brass text measured 4.32:1 on first-screen buttons | Light brass `#9d6a0f`, darker hover. Final 4.664:1 rest / 5.730:1 hover. Shared muted/error/status tokens also corrected; placeholder follow-up rose from 4.384:1 to 4.516:1. All 12 follow-up pairs and final probe pass. |
| High / Accessibility | `web/wallet.js:142`: native dialog alone let the second Tab leave its control cycle in Chromium | Explicit first/last Tab wrapping, Escape and focus return. Initial interaction failure fixed; automated case passes and visible Close focus inspected in the browser tool. |
| High / Accessibility | `web/app.js:231`: reference NFT tiles had button roles but click-only handlers | Native button tiles, names, pressed/disabled state and keyboard selection. Space → selection → escrow calldata validated in Chromium. |
| High / UI | `web/app.js:310`, `web/app.js:351`: reference enabled some write controls on the wrong network and allowed repeat clicks during approval | Central action gating, operation lock, fresh account/chain checks before sending and an account-bound workflow. Wrong-chain and pending-state tests pass. |
| High / Writing + UI | `web/app.js:257`: failed feed reads could be overwritten one second later by an old “synced” label | Separate online/stale/error state and stopped wheel; no synthetic data fallback. Failure after success remains offline in the timed browser test. |
| High / UI | `web/app.js:49`, `web/app.js:123`: failed log scans could appear as an empty complete result | Incomplete/failed scans throw into explicit history errors. No false “No open positions” in the failure test. |
| Medium / Writing | `web/app.js:144`, `web/app.js:321`, `web/index.html:118`: invalid account entry did nothing, and previous account figures could survive a failed refresh | Named inline status, `aria-invalid`, visible retry instruction, clearing stale account figures and generation guards. Valid/invalid/offline lookup cases pass. |
| Medium / UI | `web/app.js:33`, `web/app.js:383`: excessive decimal precision was silently truncated and withdrawals silently clamped | Reject precision above 18 decimals and amounts above the relevant balance/credit. Rejection and exact 1.25-SQK/2-share calldata tests pass. |
| Medium / UI | `web/app.js:213`, `web/app.js:373`: a historical NFT transfer could be labelled self-staked for a later depositor; allowance could come from the viewed account | Read the staking contract's actual `depositor(address,uint256)`; read allowance for the connected account before approval. Self-staked custody test passes. Selector `0x5e020ebb` was checked against the live staking implementation's Sourcify ABI. |
| Medium / Layout + Typography | `web/styles.css:45`, `web/styles.css:245`: intermediate desktop KPIs were hidden with no scroll affordance; small-screen forms had cramped fields | Ticker stays horizontally scrollable, mobile amount inputs use 16px and escrow occupies its own form row. Multi-width tests, 1200px scroll check and final layout probe pass. |
| Medium / Accessibility + UI | `web/index.html:9`, `web/tools/build.mjs`: missing favicon/social image and extensionless source paths on ordinary static hosts | Local metadata assets and generated `.html` source pages; asset integrity, all source links and share probe pass. |

There are no unresolved high or medium findings in the implemented scope. The network-add fallback was typechecked and source-reviewed; wrong-network switching was
exercised by the mock provider. Reduced-motion preference changes were checked in the rendered
wheel. No new protocol addresses or transaction recipients were invented.

## Evidence and limitations

- `screenshots/mobile-390.png` and `screenshots/desktop-1440.png` are final taste-probe captures
  from the actual export with real network reads. `screenshots/mobile-dark-390.png` is from the
  deterministic interaction run, with a recorded test-only feed response; its dark styles are
  unchanged by the final light-token correction. The worker opened and inspected these images.
- `taste.json`, `interactions.json`, `rendered-contrast.json`, `motion-and-ticker.json` and
  `deployment-verification.json` retain actual check results. No screenshot is a screen-reader test.
- Public RPC/API requests occasionally timed out or failed during review. Successful live reads
  and the failure/retry UI were both observed. The final probe reported no script errors or missing
  local resources. Browser graphics warnings are not claimed absent.
- Real funded-wallet signing, liquidation/sweeping on chain, passkey creation, wallet-app handoff,
  WebKit, physical mobile devices, screen readers and native 200% zoom remain unperformed.
  The existing Foundry tests were not rerun; contract source was unchanged.
- The static export is usable without a wallet for live data and account lookup, but live data
  still requires the named external API/RPC services. Fee history is an approximate block window;
  history scans retain the reference's finite range. Contract approval/slippage semantics are
  retained and documented in the README.

**Complete for the stated scope**, with the explicit verification limitations above. The source,
lockfile, assets, deployment record, static export and documentation are ready for submission.
