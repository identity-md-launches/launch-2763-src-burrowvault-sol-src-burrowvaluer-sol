# Burrow website validation

Complete for the stated frontend scope. This is the worker's local validation record, not an independent certification. No contract was deployed and no transaction was broadcast.

## Scope and assumptions

Rebuilt the operator's current financial district from https://burrow-squeek.vercel.app/ into the existing vanilla app and wallet dialog. The operator's palette, typography, panel structure, clay wheel, voxel treatment and garage remain the visual direction. The hero copy was shortened and its main actions retained. Libraries moved to assets/ because the pinned publisher omits vendor/. Source pages are generated from this repository rather than depending on Vercel route rewrites.

The config and global Three.js build are byte-identical to the operator capture. operator-reference.json records the reference URL, capture completion time, hashes and adaptations. Existing Solidity sources, dependency manifests, lockfiles and Foundry configuration were preserved. All seven protocol source hashes and Sourcify exact matches were checked; the deployment record now includes WheelBond, WheelStock and HamsterGarage.

## Assignment coverage

| Requirement | Result and evidence |
| --- | --- |
| Usable, responsive website and primary interactions | Checked in Chromium at 320, 390, 768, 1120 and 1440px, light and dark; 34 interaction cases passed. |
| Editable web/ and finished dist/ with source and lockfile | Implemented. Existing web/package.json and web/package-lock.json unchanged; production build generates a 47-file static export and web/source/. |
| Same live app and preserved wallet chooser | Wheel-native panels, all three scenes, original loans/lending and EIP-6963/mobile/Coinbase chooser retained. See operator-reference.json and interactions.json. |
| No runtime vendor/ or node_modules/; libraries under assets/ | Implemented and checked by the production export guard and final path scan. |
| Same-origin scripts under script-src 'self' | Checked with that response policy on the subpath preview. Three.js and the lazy Coinbase SDK are local assets. |
| Complete offline static export with relative URLs | 132 static references checked; every local script, font, image and source link exists. Offline probe passed; remote chain/API data is explicitly unavailable offline. |
| Hero clay hamster follows live RPM and rests at idle | Scene inspected with real API samples reporting both idle and running. Manual browser inspection recorded 72.1 RPM and subsequent animation frames; controlled 30 RPM, idle coast, stale/offline feed and changing reduced-motion preference were checked separately. |
| Six Squeek tokenURI voxel previews | Six live on-chain previews rendered; IDs 1, 222, 1111, 3333, 5555, 8888 are labeled collection previews, never wallet holdings. |
| Garage 3D scene | Rendered from the operator's scene and inspected on mobile/desktop. |
| Three panels read live Sepolia; writes use config addresses | Real public stats checked. Mock-wallet calldata was decoded against Sourcify ABIs for mint/redeem/stake/unstake, lock/redeem/exit and park/claim/leave. No real signature. |
| Config contract addresses equal operator config | Whole config byte equality checked during live-browser validation, beyond just the three new addresses. |
| Product and main action on first screen at 390 | Yes; primary action bottom 420.19px in a 390×844 viewport. screenshot: screenshots/light-390.png. |
| Title, favicon, description, og:title and og:image | Present; share probe passed, OG asset included locally. |
| Production build, typecheck and useful validation | Actual commands/results below. |
| Better Interface review and final design documentation | All six domains covered below; implemented tokens and behavior in ../../DESIGN.md. |
| Install, preview and rebuild documentation | Root README contains build/preview/install/typecheck/test commands and network/browser limitations. |

Hosting is the delivery plane's later step. This assignment prepares dist/; it does not publish or deploy the site.

## Better Interface coverage

The pinned Better Interface workflow and core principles for all six domains were read and applied during implementation. Supporting focus/forms, motion/reflow, typography and contrast sections were consulted. The original visual system remains authoritative.

| Domain | Coverage | Evidence and remaining subchecks |
| --- | --- | --- |
| Accessibility | Checked | Native buttons/links/dialog, input names and descriptions, progress semantics, live errors, NFT Enter/Space selection, wallet Tab trapping/Escape/focus return, wrong-network and disabled states, dynamic reduced motion. Keyboard interaction cases and wallet screenshot. Screen reader, voice control and physical-device checks not performed. |
| Layout | Checked | Main actions visible at 390; ten width/theme combinations without page overflow; tables scroll locally; new forms stack; long values wrap. Live screenshots and probe. Native browser zoom and localization/RTL not performed. |
| Writing | Checked | Five-word headline plus one plain sentence; unit-aware errors adjacent to forms; explicit collection preview, fee/penalty/lock terms, unavailable data and retry states. First-screen prose: 11 words at 390. No new marketing sections. |
| Typography | Checked | Local Geist and Geist Mono loaded; two weights; numeric data tabular; no clipped values. Probe reports five repeated sizes plus two single-use sizes per viewport, within its six-repeated/eight-total thresholds. The operator's size hierarchy was retained. Native iOS focus zoom not tested; mobile input size is 16px in source. |
| Colors | Checked | Existing semantic tokens retained across both themes. Offline art label and scene-caption contrast repaired; measured caption pairs 7.58:1 light / 7.25:1 dark, fixed art fallback pair 16.59:1. contrast.json records scope. Text inside the artwork is not measured. |
| UI | Checked | Shared panel/button/input states, local icons, transaction locking/confirmation/rejection/revert/retry, clay scenes, reduced motion and idle stopping. Probe finds no transition:all or persistent animation under reduced motion. 34 of 36 probed controls are below the comfortable 44px size, but all meet its 24px-or-spacing baseline; compact operator controls retained. |

Search, filtering, localization, drag-and-drop, video and additional themes are not applicable to this assignment; no new controls were invented for review coverage.

## Findings, fixes and rechecks

| Severity / source | Reproduction or evidence | Correction and recheck |
| --- | --- | --- |
| High — export libraries: web/wallet.js:120; web/index.html:227; web/tools/export-check.mjs:6 | Prior export used vendor/, which this publisher removes; wallet SDK and Three.js would be missing. | Both libraries now live in assets/. Build rejects vendor/, node_modules/, symlinks, missing references and external scripts. Production export and local SDK import passed under script-src 'self'. |
| High — write readiness/account changes: web/app.js:298; web/app.js:379; web/app.js:573 | Wheel actions must not use a disconnected account, wrong chain or failed account read. A multi-step approval can outlive its account. | Version account reads, gate row and form actions, serialize operations, and check provider chain/accounts before every send. Wrong-chain, read failure/recovery and disconnect-during-approval cases passed. |
| Medium — amount/term validation: web/app.js:397; web/app.js:415; web/app.js:448 | Invalid decimals, excessive balances, fractional work or a park below 100 HMTR must stop before requesting a signature. | Inline announced errors, focus/aria-invalid, balance checks, whole-work bounds and integer calldata. Interaction cases passed with zero mock sends for invalid inputs. |
| Medium — art fallback contrast: web/styles.css:289 | Offline probe initially measured 1.15:1 when light-theme text inherited over the fixed dark artwork tile. | Give artwork its own #ecebe8 ink. Both live/offline contrast probes passed; declared fallback pair measured 16.59:1. |
| Medium — caption contrast over clay: web/styles.css:291 | Dark-mode caption crossed the pale scene plinth; the underlying 3D surface did not provide a stable text background. | Use opaque panel background on the caption. Browser-computed caption pairs measure 7.58:1 light and 7.25:1 dark; both screenshots inspected. |
| Medium — idle coasting on slow rendering: web/wheel.js:167 | The idle test kept receiving frames after six seconds when smoothing used a capped frame delta. | Ease angular velocity by real elapsed time while capping rotation steps. Full interaction suite passed RPM, idle stopping and preference changes. |
| Medium — static source routing: web/tools/build.mjs:28; web/app.js:641 | Extensionless source URLs depend on a server rewrite absent from the export. | Generate explicit .html links and matching source pages in web/ and dist/. All seven contract pages and source index passed under /preview/. |
| Medium — on-chain market wording: web/app.js:313; web/index.html:134 | Live hardware RPM reported 72.9 while the settled Motors market still returned closed. The inherited “hamster sleeps” market label conflated these signals. | Show the contract’s open/closed state, retain the actual exit fee and explain that market status follows settled work. Rebuilt and checked the real panel, wallet suite and probe after the correction. |
| Low — first-screen copy: web/index.html:52 | The operator's longer introduction could be shortened while preserving its headline detail and destinations. | Five-word headline, one plain sentence, two direct primary destinations. Main action ends at 420.19px at 390 wide; copy/share checks passed. |

No reproduced high or medium issue remains unresolved within the checked scope. The remaining platform and real-wallet limitations below are unverified coverage, not passed checks.

## Commands and actual outcomes

Run from the repository root on 2026-11-01 UTC:

| Command | Outcome |
| --- | --- |
| node web/tools/install.mjs | Passed; unchanged manifest/lockfile installed into disposable test/scratch/site-tooling/, npm cache under /tmp. |
| npm --prefix web run build | Passed. 47 files, 132 checked references, 1,455,929 bytes in dist/. Source hashes and configured deployment addresses checked during build. |
| npm --prefix web run typecheck | Passed; tsc --noEmit with allowJs/checkJs over app, config, wallet and all three scene scripts. |
| PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers node web/tools/test.mjs | Passed 34/34 Chromium interaction cases. Result copied from test/scratch/interactions/results.json to interactions.json. |
| node web/tools/verify-deployment.mjs | Passed all seven source/Sourcify/runtime/deployment checks; source selectors and event topics matched ABIs. deployment-verification.json. |
| PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers node web/tools/live-check.mjs | Passed real-data scene/stats/config/font/resource/layout/wallet-focus checks; live-browser.json and screenshots/. |
| PLAYWRIGHT_BROWSERS_PATH=/tmp/burrow-browsers IMD_PLAYWRIGHT="$PWD/test/scratch/site-tooling/node_modules/playwright/index.mjs" node .imd/reads/skills/design-critic/scripts/taste.mjs --out test/scratch/taste | Passed 16/16 live-export checks; result copied to taste.json. |
| Same probe with --out test/scratch/taste-offline --offline | Passed 16/16 offline checks; result copied to taste-offline.json. |
| node web/tools/export-check.mjs dist | Passed; final report also retained in submission-check.json. |
| git diff --check and final scope/bytes scan | Recorded in submission-check.json. |

After the full suite, the last HTML-only correction added named keyboard stops to both personal tables. A targeted garage claim/leave rerun passed; interaction-recheck.json retains that final-export result.

The pinned probe is an assignment input and is not delivered. The other scripts are delivered. Mock providers/feed fixtures are test-only and excluded from dist/. Useful interaction coverage includes navigation, address lookup, wallet rejection/recovery, mobile links, local Coinbase import, NFT custody/selection, lending, borrowing/repay/close, failed event history, chain/feed outages, all wheel-native operations, approval serialization, integer input validation, work locks and animation stopping.

Screenshots inspected: screenshots/light-390.png, dark-390.png, light-1440.png, collateral-390.png, garage-390.png wallet-390.png and wheel-live-390.png. These are actual production-export views using real public network reads. Deterministic fixtures are used only by interaction tests. Probe captures at 390 and 1440 were also inspected; reflow at 320 was measured. Scratch captures are not submitted.

## Limitations

- The live API reported both idle and running samples. live-browser.json captures a read-only idle sample; live-motion.json and wheel-live-390.png record a subsequent natural running sample and browser animation callbacks. The physical hardware was not directly inspected. Controlled events separately verify idle stopping and preference changes.
- No funded wallet, signature or actual Sepolia state-changing call was used. Transaction/calldata, approval, pending, confirmed, rejected and reverted behavior was checked with a deterministic EIP-1193 provider. Actual passkey creation, Coinbase sessions and phone-app handoffs remain unverified.
- WebKit was installed but could not launch: missing host libraries include libgstreamer-1.0.so.0, libgtk-4.so.1 and libpangocairo-1.0.so.0. No native Safari result is claimed. Chromium viewport emulation is not a physical iPhone test.
- Screen readers, native zoom, physical touch devices, forced colors and localized/RTL content were not exercised. Probe measurements do not establish full accessibility compliance.
- Offline completeness covers local UI/runtime assets and source pages. Current balances, feed samples and uncached tokenURI art need public network access. Explicit unavailable states and a usable Connect dialog were checked without those services.
- The operator's legacy global Three.js build logs its upstream deprecation warning. There were no observed JavaScript exceptions or missing local resources in the final live browser check. Art/canvas lettering is outside text-contrast measurement.
- Solidity unit/fork suites were not rerun for this frontend-only change. Their sources are unchanged and the seven deployed protocol sources match Sourcify exactly.
- This record describes local worker checks. The delivery plane's path/byte verifier does not independently certify behavior, hosting or transaction correctness.
