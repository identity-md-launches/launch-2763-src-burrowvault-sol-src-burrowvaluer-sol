# Burrow v2 design

## Overview

This is the operator's [Burrow reference UI](https://burrow-squeek.vercel.app), reproduced in
plain HTML, CSS and JavaScript. Its audience is Sepolia SQK lenders and Squeek NFT borrowers.
The visual idea is a working hamster wheel beside a compact lending dashboard: warm graphite
surfaces, brass actions, fine dividers and tabular figures. The same light theme follows the
system color preference. There is no added navigation system, marketing section or theme switch.

The source of truth is `web/styles.css`, with structure in `web/index.html`, dynamic panels in
`web/app.js`, the connect dialog in `web/wallet.js` and the wheel in `web/wheel.js`. The production
export copies these modules unchanged. The narrow additions at the end of the stylesheet repair
keyboard focus, mobile fields, dialog layout and contrast within the reference's system.

## Colors

Tokens are CSS custom properties in `web/styles.css:7`. The base is dark; the light overrides
are in `@media (prefers-color-scheme:light)`. Values are intentionally kept in the operator's
hex/RGBA notation.

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `--bg` | `#141413` | `#f6f5f2` | Page background |
| `--panel` | `#1a1a19` | `#fdfcfa` | Panels, header, dialog |
| `--raised` | `#242322` | `#eeece7` | Neutral buttons, row hover, wheel stage |
| `--sunk` | `#10100f` | `#e8e6e0` | Inputs and source code |
| `--ink` | `#ecebe8` | `#1c1b19` | Primary text |
| `--ink2` | `#a9a7a2` | `#55524d` | Body explanations, links |
| `--ink3` | `#8d8b86` | `#6a6761` | Hints, captions, table headings |
| `--line` | `rgba(236,235,232,.08)` | `rgba(28,27,25,.09)` | Dividers, panel outlines |
| `--line2` | `rgba(236,235,232,.14)` | `rgba(28,27,25,.16)` | Control outlines |
| `--acc`, `--warn` | `#d9a441` | `#9d6a0f` | Primary actions, focus, warnings |
| `--acc-ink` | `#1b1403` | `#fff` | Text on primary buttons |
| `--pos` | `#4cc38a` | `#15803d` | Connected/healthy/running states |
| `--neg` | `#f15b61` | `#c52222` | Network, health and transaction errors |

The reference's light brass and status/muted tokens were adjusted slightly after contrast
checks. This does not change their roles or introduce another palette. Primary-button hover
mixes the accent with 12% white in dark mode and 12% black in light mode. Status text, numbers
and button labels accompany status color. See `web/validation/validation.md` for measured coverage;
the canvas and translucent decorative layers are not blanket contrast-certified.

## Typography

`--sans` is `Geist`, followed by `ui-sans-serif`, `system-ui`, `-apple-system`, `Segoe UI`,
`sans-serif`. `--mono` is `Geist Mono`, followed by `ui-monospace`, `SF Mono`, `Menlo`,
`Consolas`, `monospace`. Both local Latin WOFF2 files are declared for weights 400–500 with
`font-display:swap`; the browser confirmed both faces loaded. They are in `web/assets/` with
their SIL Open Font Licenses in `web/licenses/`. There are no external font requests.

| Role | Size / line height | Weight / details |
| --- | --- | --- |
| Headline | `clamp(32px,3.6vw,48px)` / `1.1`; 36px at ≤640px | 500, `-.02em`, max 14ch |
| Hero description | 16px / 24px; 15px on phones | 400, max 36rem |
| Panel headings / hero actions | 15px / 20px | 500 |
| Body / controls | 14px / 20px | 400 body, 500 buttons |
| Table cells / hints / small buttons | 13px / 20px | 400, 500 on buttons |
| Captions / KPI labels / table headings | 12px / 16px | 400 |
| Empty-state heading / position figures | 20px / 28px or 24px | 500 |
| Brand / hero facts | 16px / 20px or 24px | 500 |

The operator's scale is retained: five repeated sizes and two single-use sizes per tested
entry viewport. It passes the pinned probe's six-repeated/eight-total threshold. Display type
and the empty-state title remain intentional exceptions to the body scale. Numbers use Geist
Mono and `font-variant-numeric:tabular-nums`; prose uses Geist. Inputs become 16px on phones to
avoid automatic iOS input zoom. Footer prose is limited to 72ch; empty-state prose to 48ch.

## Layout

The page follows a 4px rhythm with 8/12/16/20/24/28/32/40/48px spacings. `.wrap`, `.topin`
and `.foot` share a 1520px maximum width. The `--gut` outer inset is 24px, reduced to 16px
at 640px. `.cols` and `.col` use a 24px gap and zero-minimum grid tracks to allow reflow.

| Breakpoint | Implemented behavior |
| --- | --- |
| ≥1120px | Two dashboard columns, `1.6fr` and `minmax(360px,.9fr)`; two equal hero columns |
| ≤1119px | One dashboard column; wheel below hero copy, 360px stage; hero padding 40px 32px |
| ≤900px | Header is nonsticky and wraps; KPI strip moves to its own horizontally scrollable row |
| ≤720px | Position gauge sits above the figures instead of beside them |
| ≤640px | 16px gutters, 32px 16px hero padding, two-by-two facts, 300px stage, two-column forms, full-row amount/escrow controls, bottom wallet dialog |

The initial 390×844 screen shows Burrow, Connect wallet, the complete product headline,
description and Open a position / Lend SQK actions. The main action ends at roughly 516px,
matching the reference's composition. Tables scroll inside `.tw` rather than widening the
page; on phones their 480px minimum preserves data columns. The KPI strip is horizontally scrollable at every width, including intermediate desktop widths;
it and the table wrappers are keyboard focusable and named. Amounts/addresses in feedback wrap; full contract addresses
are available in accessible names, link titles and the source listing.

Rendered reflow was checked at 320, 390, 768, 1120 and 1440px in both themes. This is not a claim
of physical-device or native browser zoom testing. The interface is English-only; RTL and
localized layouts are not implemented.

## Elevation & depth

This is a primarily flat system. Panels use tonal separation and 1px structural outlines.
Neutral controls retain the reference's subtle inset highlight, `inset 0 1px 0 rgba(255,255,255,.06)`.
Primary buttons have no shadow. The desktop header is sticky at z-index 20. The wallet uses
the browser's dialog top layer and a `rgba(0,0,0,.6)` backdrop. Its focus ring is visible over
the dimmed page. Three.js lights, shadows and metal reflections belong only to the wheel.

## Shapes

`--r-panel:12px` and `--r-ctl:8px` define panels and controls. The hero has a 16px radius;
chips use 12px, inventory tiles 8px, step markers 4px, and status dots are 8px circles.
Inventory art occupies a square. Only the hero, tile artwork and bar treatments intentionally
clip to their shapes. Text is not ellipsized; compact account links expose their complete value.

## Components

- **Buttons and links** (`web/styles.css:53`): `.btn`, `.btn.pri`, `.btn.sm`. Rest, hover,
  active, focus and disabled states are explicit. Default controls are 36px high, small ones
  32px, and hero actions 44px. Disabled controls use 40% opacity and cannot send. Focus is a
  2px accent outline with a 2px offset. The reference's `.98` press scale is retained.
- **Panels** (`web/index.html`, `web/app.js`): `.panel`, `.ph`, `.pb`, `.kv`, `.tw` organize
  the same Position, Collateral, Open positions, Squeekchain, Lend, Risk parameters, Revenue
  and Contracts sections. The read-only/empty state leads to Connect or account lookup.
- **Account and amount inputs** (`web/index.html`): native text inputs with accessible names;
  amount fields use `inputmode=decimal`. Enter loads an account. Invalid addresses mark the
  field and announce a specific correction. RPC failures preserve a retry path through Load.
- **NFT inventory** (`web/app.js`, `.nft`): native toggle buttons with `aria-pressed`; Enter
  and Space select wallet-owned NFTs. Custodied/read-only items announce `aria-disabled`.
  Selection is limited to the vault's 32-NFT cap. On-chain SVGs load as isolated images.
- **Wallet dialog** (`web/wallet.js`): one connect pattern reused by the header and empty
  states. Rows are at least 48px high with 28px wallet marks. It lists discovered extensions,
  phone app links and Coinbase. Escape, backdrop and Close dismiss it; Tab wraps inside and
  focus returns to the opener. Request errors remain in the dialog. A connected account
  exposes its full address, Disconnect and a network-switch action when needed.
- **Transaction feedback** (`web/app.js`): named live regions distinguish confirmation in
  wallet, pending receipt, confirmed, reverted and rejected states. Buttons lock during an
  operation. Decimal precision, credit and balance bounds are checked. Receipt links remain
  available for pending transactions; changing an account cannot continue the prior workflow.
- **Wheel / gauge** (`web/wheel.js`, `web/app.js`): the operator's wheel geometry and studio
  lighting are retained with local Three.js. It follows feed RPM, stops offscreen/when hidden
  and respects reduced motion, including changes while the page is open. Missing WebGL hides
  the stage and keeps the product/actions usable. The debt gauge has a text equivalent.
- **Source pages** (`web/tools/build.mjs`): generated from current repository files using the
  same fonts, surfaces and header. Explicit `.html` links work on static gateways without
  extensionless routing. Source code remains selectable and scrollable.

The reference's 400ms entrance and 40ms panel stagger are retained. Interaction transitions
name their properties and use `cubic-bezier(.22,1,.36,1)`. Reduced motion disables entrances,
spinning indicators, animated wheel motion, transitions and smooth scrolling.

## Do's and don'ts

Use the existing `.wrap`/`.panel`/`.ph` primitives and role tokens for any future adjacent
page. Use `.btn.pri` for its main action, `.btn` for peers, and `.n`/`.m` for numeric data.
Keep the established density, full-width data and native controls. Preserve source paths and
relative asset URLs when adding another static page. Do not introduce a new font, palette,
decorative hero or framework just to extend this site. Do not present mock or cached test data
as live chain state.

The review method follows the pinned Better Interface guidance by Jakub Krehel (MIT,
`267330e1adfc66a718fb65fa6918c1f06d0a689e`) and the documentation method from Paul Bakaus's
Impeccable (Apache-2.0, `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`). Notices are retained in
`web/licenses/Design-guidance.txt`; the visual design remains the operator's reference.
