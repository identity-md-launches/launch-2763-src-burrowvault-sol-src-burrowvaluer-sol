# Burrow interface

## Overview

Burrow is a Sepolia financial district: SQK lending against Squeek NFTs, bonds measured in
wheel work, Hamster Motors shares and a garage that earns cars. This implementation keeps the
operator's warm graphite/brass dashboard, clay dioramas and compact financial tables. It uses
plain HTML, CSS and JavaScript, extending the existing wallet dialog and transaction safeguards.

The visual idea is a quiet money market powered by one real hamster wheel. The hero introduces
that relationship and links directly to Hamster Motors and Wheel bonds. Position, Collateral,
Open positions, Motors and Garage occupy the primary column; chain data, lending, bonds, risk,
revenue and contract references occupy the secondary column. DOM order becomes reading order
when the columns collapse. There are no added routes, themes or decorative font families.

## Colors

Canonical tokens are in `web/styles.css:7`; the light override starts at line 18.
`prefers-color-scheme` selects the existing themes. `data-theme="dark"` retains the source's
explicit dark override; no theme control is added.

| Token / role | Dark | Light |
| --- | --- | --- |
| `--bg`, page | `#141413` | `#f6f5f2` |
| `--panel`, panels/dialog | `#1a1a19` | `#fdfcfa` |
| `--raised`, controls/scene | `#242322` | `#eeece7` |
| `--sunk`, inputs/tiles | `#10100f` | `#e8e6e0` |
| `--ink`, primary text | `#ecebe8` | `#1c1b19` |
| `--ink2`, supporting text | `#a9a7a2` | `#55524d` |
| `--ink3`, labels/metadata | `#8d8b86` | `#6a6761` |
| `--acc`, action/focus | `#d9a441` | `#9d6a0f` |
| `--acc-ink`, action label | `#1b1403` | `#fff` |
| `--pos`, positive | `#4cc38a` | `#15803d` |
| `--neg`, error | `#f15b61` | `#c52222` |
| `--warn`, warning | `#d9a441` | `#9d6a0f` |
| `--line`, structure | `rgba(236,235,232,.08)` | `rgba(28,27,25,.09)` |
| `--line2`, controls/dividers | `rgba(236,235,232,.14)` | `rgba(28,27,25,.16)` |

Status also has text: connected/wrong network, running/idle/offline, confirmed/reverted and
bond progress percentages. Color is not the only signal. Artwork has a fixed `#0b0a09`
background, with `#ecebe8` for its unavailable label. The scene caption has an opaque
`--panel` background so clay geometry cannot determine its contrast. The browser-computed
caption pairs measure 7.58:1 in light mode and 7.25:1 in dark mode. The artwork fallback pair
measures 16.59:1. Measurements and scope are in `web/validation/contrast.json`; these values do not
claim contrast for lettering inside the 3D art.

## Typography

Both font files are local under `web/assets/`: `geist-latin.woff2` and
`geist-mono-latin.woff2`, licensed under SIL OFL. Their `@font-face` declarations request normal
weights 400–500 with `font-display:swap`. Actual font loading was checked in Chromium.

- `--sans`: Geist, UI/system sans, Apple/Segoe UI fallbacks. Prose, controls and headings.
- `--mono`: Geist Mono, UI monospace, SF Mono/Menlo/Consolas fallbacks. Amounts, timestamps,
  addresses, source code and tabular data. Changing numbers use `tabular-nums`.

| Role | Size / line height | Weight |
| --- | --- | --- |
| Hero | `clamp(32px,3.6vw,48px)` / 1.1; 36px on phones | 500 |
| Position figures / empty title | 20px / 24px or 28px | 500 |
| Brand / facts / desktop description | 16px / 20px or 24px | 400–500 |
| Section title / hero action / mobile description | 15px / 20px or 24px | 400–500 |
| Body / standard controls | 14px / 20px | 400–500 |
| Tables / panel hints / small controls | 13px / 20px | 400–500 |
| Data labels / status / caption | 12px / 16px | 400–500 |

The probe found five repeatedly used sizes and two single-use sizes per disconnected viewport,
within its six-repeat/eight-total threshold. Connected position figures use the existing 20px
step. SVG gauge annotations and canvas artwork are separate graphics. The hero uses balanced
wrapping, `-.02em` tracking and a final `16ch` measure. Supporting hero copy is capped at 36rem;
footer paragraphs at 72ch. Body copy has natural tracking. Amount/address feedback wraps rather
than truncates. Mobile inputs use 16px to avoid the usual iOS focus zoom; native-device behavior
was not tested.

## Layout

The existing 4px spacing rhythm supplies 4/8/12/16/20/24/28/32/40/48px steps. `.wrap` and
`.topin` cap content at 1520px. Page gutters are 24px, falling to 16px on phones. Panel gaps are
24px; panel bodies and forms use 16px padding with 8px within form groups. The hero has 48px
copy padding on desktop, 40px 32px below 1120px and 32px 16px on phones.

| Breakpoint | Implemented behavior |
| --- | --- |
| ≥1120px | Split hero; main grid `minmax(0,1.6fr) minmax(360px,.9fr)` |
| ≤1119px | Hero and panels stack; wheel stage is 360px high |
| ≤900px | Header becomes static; metrics move to a named, focusable scrolling strip |
| ≤720px | Position gauge moves above its figures |
| ≤640px | 16px gutters, stacked hero actions, two-column facts, 300px wheel stage, 280px garage |

On phones the HMTR amount occupies a full row above three buttons. Bond amount and work term
share a row, with Lock below. Other forms preserve their two-column adaptations. Definition
lists allow both columns to wrap; values have a 32ch cap. Inventory uses auto-filling columns
with a 96px minimum and 8px gaps. At 390px the six previews form two rows of three.

Tables scroll inside `.tw` instead of widening the page. Their 480px mobile minimum retains
financial columns; each scroll container has a keyboard stop and accessible name. Source pages
use explicit `.html` links and selectable, separately scrollable code. Real-data Chromium checks
covered 320, 390, 768, 1120 and 1440px in both themes without page overflow. The primary hero
action ends at 420.19px in the 390×844 first screen. Native browser zoom, RTL/localized layouts
and physical devices remain unverified.

## Elevation & depth

Panels use flat tonal separation and structural 1px outlines. Neutral buttons retain the
operator's subtle inset white highlight; primary buttons have no shadow. The desktop header
is sticky at z-index 20 and becomes static on narrow layouts. The wallet uses the native dialog
top layer with a `rgba(0,0,0,.6)` backdrop. Scenes use Three.js lights and shadows; their depth is
confined to the artwork. The caption is an opaque flat label over the wheel scene.

## Shapes

`--r-panel:12px` and `--r-ctl:8px` define panels and controls. The hero has a 16px radius,
wallet/network chips 12px, inventory tiles 8px, caption and step markers 4px, and status dots
are 8px circles. Tiles and the hero clip artwork to their shape. Financial values and error
messages are not ellipsized. Bond progress has a 4px bar, a numeric percentage and accessible
progress values.

## Components

- **Actions** (`web/styles.css:53`): `.btn`, `.pri`, `.sm` have explicit hover, press, focus and
  disabled states. Standard/small/hero heights are 36/32/44px; wallet rows are at least 48px.
  Focus is a 2px accent outline with 2px offset. The operator's `.98` press scale is retained.
  The dense dashboard meets the 24px target baseline; many controls are smaller than the
  comfortable 44px target, which the probe reports.
- **Panels and forms** (`web/index.html`): `.panel`, `.ph`, `.pb`, `.kv`, `.form`, `.tw` reuse
  the same surfaces and reading hierarchy. Inputs have accessible names and nearby unit,
  fee and maturity explanations. New field errors mark `aria-invalid`, focus the field and
  announce a correction through a stable status region. Editing clears the invalid state.
- **Collateral** (`web/app.js:265`, `web/nft3d.js`): six preview IDs are explicitly collection
  previews, never wallet holdings. `tokenURI` supplies on-chain data-image art; one shared
  WebGL context produces voxel reliefs copied to tile canvases. Missing WebGL retains the
  image. Wallet-owned items use native toggle buttons, support Enter/Space and enforce the
  32-NFT limit. Staked items are not selectable; their depositor is checked.
- **Wheel and garage** (`web/wheel.js`, `web/garage3d.js`): preserve the operator's clay
  geometry and lighting using the local `assets/three.min.js`. The wheel follows measured
  RPM and coasts to rest using elapsed time, including on slow renderers. It stops when
  hidden/offscreen or the feed fails. Reduced-motion changes stop animation immediately;
  NFT pointer tilt also honors preference changes. The garage renders once per resize.
- **Wheel contracts** (`web/app.js:286`): live global stats and versioned account reads for
  Motors, bonds and garage. Failed reads disable affected actions and expose Load/automatic
  retry. Stake/garage exit locks, bond progress, maturity, fees, balances and units are
  visible. The Motors market's on-chain open/closed status is distinct from live hardware RPM.
  Contract addresses and calldata selectors match the verified deployments.
- **Wallet sheet** (`web/wallet.js`): preserved EIP-6963 discovery, browser-wallet fallback,
  four phone links and local Coinbase SDK. There is one shared connection pattern. Escape,
  Close and backdrop dismissal return focus to the opener; Tab remains in the modal. The
  wrong chain offers Switch to Sepolia with an add-chain fallback. A connected sheet shows
  the full address and Disconnect. Real passkey and phone-app handoffs were not exercised.
- **Transactions** (`web/app.js:550`): one operation locks related controls through approvals
  and receipt polling. Confirmation, pending, success, revert and rejected states are distinct.
  Provider/account/chain are checked before sending. Account changes cannot continue an old
  approval flow. Pending explorer links remain available on a receipt timeout.

Entrance animations retain the operator's 400ms timing and 40ms panel stagger. Transitions name
the properties they affect and use `cubic-bezier(.22,1,.36,1)`. Reduced motion disables entrances,
spins, tilts, transitions and smooth scrolling. There is no `transition:all`.

## Do's and don'ts

Start an adjacent surface with `.wrap`, `.panel`, `.ph` and `.pb`, using the existing role tokens.
Use `.btn.pri` for its main action, neutral `.btn` for peers and `.n` for data. Keep unit labels,
fees and consequential terms beside controls. Keep runtime scripts, fonts and images inside
`assets/` or beside `index.html`, with relative URLs. Extend the build's integrity checks when
adding another asset type. Never introduce a `vendor/` or `node_modules/` runtime directory,
external script dependency, fabricated live balance or hidden transaction result.

Design review follows Jakub Krehel's Better Interface (MIT,
`267330e1adfc66a718fb65fa6918c1f06d0a689e`); the documentation method follows Paul Bakaus's
Impeccable (Apache-2.0, `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`). Their notices remain in
`web/licenses/Design-guidance.txt`. The visual identity remains the operator's reference.
