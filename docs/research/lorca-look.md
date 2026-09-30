# How Lorca's look is built

Research for [ticket #22](https://github.com/saiashirwad/sendpoint/issues/22), supporting [redesign map #21](https://github.com/saiashirwad/sendpoint/issues/21). Observed 2026-09-30.

## Conclusion

Lorca is an Inter-and-zinc editorial scrolling tour: a narrow frosted pill navigation, oversized tightly tracked hero, and wider rounded panels that each explain one idea. Thin translucent borders—not panel shadows—separate surfaces. Colour is concentrated in pixel-art illustration wells, small violet icons, and a hand-drawn underline; the primary buttons are monochrome. For Sendpoint, borrow the geometry, hierarchy and system light/dark behaviour, but replace the violet/azure/cyan decoration with the map's single raspberry accent and use real Sendpoint screenshots. This is a recommendation, not a claim that Lorca uses raspberry. [H][C][M]

## Sources and method

- **[H]** [Lorca home page](https://lorca.app/): first-party server-rendered HTML, classes, assets and content.
- **[C]** [Deployed stylesheet, styles-CUe-CPVw.css](https://lorca.app/assets/styles-CUe-CPVw.css): first-party compiled CSS; identifies Tailwind CSS **4.3.3**. All CSS values below come from this stylesheet and the corresponding classes in [H]. Hashed asset URLs can change on deploy.
- **[F]** [Google Fonts request used by Lorca](https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap): Inter weights 400, 500, 600, 700 with `display=swap`, linked by [H].
- **[M]** [Sendpoint redesign map](https://github.com/saiashirwad/sendpoint/issues/21): target audience, raspberry accent, light/dark, Astro and existing Worker constraints.
- **[B]** Browser verification: Playwright Chromium 153, full-page captures below at device scale factor 1, desktop viewport 1440×1000 and mobile viewport 390×844. Emulated `colorScheme` light/dark; waited for fonts and decoded images, including eager loading the otherwise lazy screenshot. Computed body background matched the light/dark tokens; computed heading family began with Inter. Document scroll width equalled viewport width in all four cases. Opened the first FAQ and confirmed a region with text and `0.2s ease-out accordion-down` animation.

Pixel equivalents below assume the observed default 16px root size; rem values are the transferable source of truth. This is a deployed-site inspection, not access to Lorca's source repository.

## Reference screenshots

These are unmodified full-page captures of the live site, with the FAQ closed. They are references, not proposed Sendpoint designs. [B]

| Desktop (1440px wide) | Mobile (390px wide) |
| --- | --- |
| [Light](lorca-look/desktop-light.png) | [Light](lorca-look/mobile-light.png) |
| [Dark](lorca-look/desktop-dark.png) | [Dark](lorca-look/mobile-dark.png) |

The app screenshot stays the same light image in both schemes: [H] uses one `/screens/group.png`, not a scheme-specific picture source. The surrounding panel, text, navigation and diagram cards change. [H][B]

## Typography

The default sans stack is `"Inter", -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`. The mono stack is `"SF Mono", ui-monospace, Menlo, monospace`, used for the numbered setup steps. HTML enables antialiasing and `text-rendering: optimizelegibility`. [C][H]

| Role | Size and line height | Weight / tracking |
| --- | --- | --- |
| Hero h1 | 3.4rem / .98; at ≥640px 4.6rem; at ≥1024px 5.2rem (54.4 / 73.6 / 83.2px) | 600, −.035em (`.display`) |
| Section h2 | 2.25rem / .98; ≥640px 3rem / .98 | 600, −.035em |
| Final CTA h2 | 2.25rem, ≥640px 3.75rem; line height .98 | 600, −.035em |
| Hero description | 1.125rem / 1.75rem; ≥640px 1.25rem / 1.75rem | 400, muted |
| Section descriptions | 1.125rem, line height 1.625 (29.25px) | 400, muted |
| Body / card titles | 1rem / 1.5rem; tool descriptions use 1.625 line height | body 400; titles 600 |
| Navigation / small copy | .875rem / 1.25rem | navigation 400; buttons 500 |
| Eyebrows | .75rem / 1rem | 600, .18em, uppercase, muted at 80% |
| Availability pill | .75rem / 1rem | 500 |

Values are from [H][C]. `.display` overrides the generic heading utilities' line heights: do not accidentally implement h2 at Tailwind's default 40px line height. Hero uses `text-wrap: balance`, description uses `pretty`; the English hero also contains an explicit `<br>`. Chinese has separate heading size/line-height overrides and should not be inferred from the English captures. [H][C]

## Colour tokens: exact CSS

These are custom zinc-like OKLCH values, not simply the stock zinc palette. [C]

| Token | Light | Dark |
| --- | --- | --- |
| `background` | `oklch(98.5% .002 285)` | `oklch(13% .005 285)` |
| `foreground`, `card-foreground`, `popover-foreground` | `oklch(17% .005 285)` | `oklch(97% .002 285)` |
| `card`, `popover` | `oklch(100% 0 0)` | `oklch(17% .005 285)` |
| `primary` | `oklch(17% .005 285)` | `oklch(97% .002 285)` |
| `primary-foreground` | `oklch(98.5% .002 285)` | `oklch(15% .005 285)` |
| `secondary`, `muted`, `accent` | `oklch(95% .003 285)` | `oklch(24% .006 285)` |
| `secondary-foreground`, `accent-foreground` | `oklch(17% .005 285)` | `oklch(97% .002 285)` |
| `muted-foreground` | `oklch(48% .01 285)` | `oklch(68% .01 285)` |
| `border` | `oklch(0% 0 0 / .1)` | `oklch(100% 0 0 / .1)` |
| `input` | `oklch(0% 0 0 / .14)` | `oklch(100% 0 0 / .14)` |
| `ring` | `oklch(60% .02 285)` | inherited same value |
| `destructive` | `oklch(58% .22 25)` | `oklch(66% .2 25)` |
| `sidebar` | `oklch(97.5% .003 285)` | `oklch(15% .005 285)` |
| `sidebar-accent` | `oklch(93% .004 285)` | `oklch(24% .006 285)` |

`--violet: #6b66f5`, `--azure: #3d85f0`, `--cyan: #2eb3dc` stay constant. Selection is white on `oklch(55% .18 280)`. The small availability dot is emerald-500 in light (`oklch(69.6% .17 162.48)`) and emerald-400 in dark (`oklch(76.5% .177 163.223)`). [C][H]

Dark tokens and Tailwind `dark:` utilities are controlled by **`@media (prefers-color-scheme: dark)`**; `color-scheme` is explicitly light/dark. No manual home-page theme switch is present in the inspected markup. Documentation `--color-fd-*` tokens are mapped onto the same custom tokens, but this research does not audit the `/docs` layout. [C][H]

## Widths, spacing and responsive layout

Tailwind's spacing unit is `.25rem` (4px). Relevant breakpoints are `sm` 40rem/640px, `md` 48rem/768px, `lg` 64rem/1024px. [C]

| Element | Geometry |
| --- | --- |
| Navigation / hero | `max-w-4xl`: 56rem (896px); hero horizontal padding 20px |
| Feature section outer wrappers | `max-w-6xl`: 72rem (1152px), horizontal padding 20px, vertical padding 40px |
| Feature headings / paragraphs | `max-w-3xl`: 48rem (768px) |
| Hero description | `max-w-2xl`: 42rem (672px) |
| App screenshot | width 100%, `max-w-5xl`: 64rem (1024px) |
| FAQ wrapper | `max-w-3xl`: 48rem, horizontal padding 20px, vertical padding 64px |
| Hero top padding | 80px, ≥640px 112px |
| Hero internal spacing | badge bottom 20px; paragraph top 28px; buttons top 36px, gap 12px; note top 16px |
| Hero-to-tour spacer | 64px, ≥640px 96px, followed by first section's 40px top padding |
| Feature copy padding | horizontal 24px / ≥640px 48px; top 40px / 56px; bottom 32px |
| Feature internal spacing | eyebrow→heading 12px; heading→paragraph 20px |
| Illustration well padding | horizontal 16px / ≥640px 48px; vertical 40px / 56px |

All geometry: [H][C]. Max widths include padding because the reset uses border-box. At 1440px, a feature wrapper is 1152px wide and its panel is 1112px wide; at 390px, the panel is 350px wide. Adjacent feature wrappers produce 80px between panels (40px bottom + 40px top). [H][C][B]

Page order is hero → group-chat screenshot panel → privacy diagram panel → tools grid panel → getting-started panel → narrower FAQ → colourful final download banner → footer. Each feature has an eyebrow, succinct heading and explanatory paragraph before its visual. There is no screenshot crammed into the hero. [H]

The tools grid is one column, two at ≥640px, four at ≥1024px. Its 1px gap on a border-coloured background makes shared dividers, with card-coloured cells and 24px/32px horizontal, 32px vertical padding. Getting started uses a 40px gap and equal two-column layout at ≥1024px; otherwise it stacks. Its panel has 24px/48px horizontal and 48px vertical padding. Steps have 16px padding, 16px corner radius, 20px vertical gaps and a 3%-foreground tint. Hero buttons stack below 640px. Desktop nav links disappear below 768px; brand, language link and download remain, with no hamburger in the inspected header. [H][C]

## Frosted pill navigation and buttons

Header: `position: sticky; top: 16px; z-index: 40; margin-top: 16px; padding-inline: 16px`. The inner pill is 56px tall, max 896px wide, fully rounded, with left/right padding 20px/16px. Light background is zinc-200 at 50% (`oklch(92% .004 286.32 / .5)`); dark is zinc-900 at 80% (`oklch(21% .006 285.885 / .8)`) plus a 1px token border. `backdrop-filter: blur(24px)` supplies the frost. There is no specified pill shadow or light-mode border. Logo image is 40px, brand gap 8px, nav gap 24px, right-control gap 12px. [H][C]

Header Download is 32px high with 16px horizontal padding. Hero buttons are 48px high; primary has 28px horizontal padding and secondary 24px. All are full pills, 500 weight. Primary uses the monochrome primary tokens and 90% primary on hover. Secondary is transparent, bordered, explicitly shadowless and gets a 5%-foreground hover fill. Focus-visible treatment is a 3px ring at 50% ring colour plus ring-coloured border. These interaction treatments are worth retaining when replacing the accent. [H][C]

## Panels, screenshots and decoration

`.panel` is `background: var(--card); border: 1px solid var(--border); border-radius: 28px`, without its own shadow. Feature panels clip their illustration wells with `overflow: hidden`. [H][C]

`.window-frame` uses a 1px white-at-15% border and `border-radius: calc(var(--radius) + 4px)`, with `--radius: .75rem`: 16px at the default root size. At ≥640px it explicitly uses 1rem, also 16px. Its shadows are:

```css
/* Light */
--window-shadow: 0 40px 100px -30px #1e1b4b59;
/* Dark */
--window-shadow: 0 40px 120px -30px #000c;
```

The screenshot is an actual 1568×993 image with intrinsic dimensions, lazy loading and async decoding—not HTML imitation window chrome. Colourful backgrounds are raster assets: [`/pixels/2.png`](https://lorca.app/pixels/2.png) behind the screenshot, [`/pixels/8.png`](https://lorca.app/pixels/8.png) behind the diagram, and [`/pixels/11.png`](https://lorca.app/pixels/11.png) behind the closing CTA. They use cover, centre, and `image-rendering: pixelated`. [H][C]

`.grain::after` overlays an SVG fractal-noise texture (`baseFrequency=.9`, `numOctaves=2`, 160px tile, inner opacity .6), with overall opacity .35, overlay blend mode and no pointer events. The hero `.brush` is an inline SVG wavy stroke, not a text gradient: violet→azure→cyan, stroke width 6 in a 200×14 viewBox, background sized `100% .22em`, bottom aligned, `.04em` bottom padding. [C]

Closing CTA has 28px corners, 80px vertical / 24px horizontal padding, a 64px icon, white heading/copy, and a white pill with zinc-900 text. The wrapper has 80px bottom padding. Footer has a top border and 32px vertical padding. [H][C]

## Diagram recipe

The privacy diagram is ordinary flexbox with three translucent cards and two animated wires, within an 896px maximum container. It is a column on mobile, row at ≥640px. Cards have max-width 256px, desktop width 208px, 20px padding, 16px corners, and 12px backdrop blur. Light fill/border are white at 85%/50%; dark fill is zinc-900 at 80% with white-at-10% border. `shadow-xl` is `0 20px 25px -5px #0000001a, 0 8px 10px -6px #0000001a`. Icon circles are 44px, inner Lucide icons 20px with 1.75 stroke width; the middle circle has a violet→cyan gradient. Labels are semibold with 14px muted explanation. [H][C]

Wires are 2px wide × 64px tall on mobile; at ≥640px they are 2px tall and flex to fill horizontal space. Base is white at 35%, with a moving white highlight. The wrapper has `role="img"` and an explanatory accessible label; decorative backgrounds are `aria-hidden`. Adapt this simple diagram vocabulary to Sendpoint's own workflow rather than copying Lorca's computer/relay/phone story. [H][C]

## FAQ and motion

FAQ uses Radix-style accordion markup: h3/button triggers with `aria-expanded`, linked labelled regions, `data-state`, and hidden closed content. Rows use 1px bottom borders except the last; triggers are 16px, weight 500, with 16px vertical padding and 16px gap. The 16px chevron is shifted down 2px and rotates 180° over 200ms when open. Content wrapper is 14px and clips overflow. Opening animates height from 0 to the measured Radix content height; closing reverses it, both 200ms ease-out. Browser opening of the first item verified the animation and revealed its answer. [H][C][B]

The main motion is restrained: smooth anchor scrolling, default 150ms transitions with `cubic-bezier(.4,0,.2,1)`, accordion transitions, and wire highlights. Wire sweep lasts 5s, repeats infinitely with `cubic-bezier(.45,0,.25,1)`, travels from −100% to 200% by 45% of the cycle, then holds through the end. Second wire inherits a −2.5s delay. Mobile uses a vertical gradient/sweep; desktop a horizontal one. No hero entrance or scroll-reveal animation is specified by the inspected home markup/CSS. [H][C]

**Accessibility caveat:** no `prefers-reduced-motion` rule was found in the deployed stylesheet. Do not copy that omission: the Sendpoint implementation should disable smooth scroll and repeating decorative motion when reduced motion is requested. Contrast has not been formally audited; especially check raspberry and muted text before shipping. [C; recommendation]

## Style-tile handoff for Sendpoint

Recommended starting specification, constrained by [M] and grounded in the measurements above:

1. Inter 400/500/600/700; keep the 600-weight, −.035em display style and compact .98 line height, but validate wrapping with Sendpoint's own copy.
2. Use the neutral light/dark table as a baseline, with 28px feature panels, 16px inner cards, 1px 10%-contrast borders and full-pill controls.
3. Keep 896px nav/hero, 1152px tour and 768px FAQ wrappers, 20px page gutters, and 80px panel-to-panel spacing.
4. Substitute one raspberry accent for the colourful underline/icons/illustration treatment. Do not introduce Lorca's violet/cyan gradient as a second brand palette. Exact raspberry token selection remains a Sendpoint design decision, not resolved by Lorca research.
5. Keep the hero short and download-led. Put the real app screenshot and redesigned existing demo in their own tour sections; illustrate article/PDF work rather than Lorca's developer-oriented examples.
6. Build the style tile with both schemes, a 390px mobile width, a desktop width, primary/secondary/focus states, one framed real screenshot and one expanded FAQ row. Include reduced-motion handling.

## Limits and verification

- Observations describe the live deployment on the date above; future deploys can change the hashed stylesheet and assets.
- Four screenshot references cover desktop/mobile and light/dark, not every intermediate breakpoint, browser, keyboard path or open FAQ combination.
- Browser computed font family and font readiness were checked; individual glyph font fallback was not audited.
- No source-repository provenance, asset reuse licence, full accessibility audit, or `/docs` design audit was established. Treat screenshots as research reference, not production assets to copy.
- This ticket changes documentation only; no Sendpoint UI or website implementation is included.
