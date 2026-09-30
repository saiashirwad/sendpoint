# Seeing and checking the Astro site

Resolution of [#32](https://github.com/saiashirwad/sendpoint/issues/32), in the [redesign map](https://github.com/saiashirwad/sendpoint/issues/21). Researched 2026-09-30.

## Decision

Use **Playwright Test + its pinned Chromium**, with a root `./site-shots.sh` entry point once Astro lands. Capture each public page at **1440×1000 and 390×844**, in **light and dark**, at 1× scale, using `toHaveScreenshot({ fullPage: true })`. Initially `/` and `/docs` make eight images. Keep app `./shots.sh` unchanged. This is a recommendation for adoption, not an Astro migration in this ticket.

Playwright already supplies viewport/color-scheme emulation, stable screenshot assertions, image comparison, failure artifacts, and an owned local server; an extra screenshot service or custom pixel-diff implementation is unnecessary for this small site.[1][2][3][4] Astro documents Playwright as an end-to-end testing option.[5] Browser screenshots are also what an agent should **look at**, not merely count: a matching baseline can still have bad copy or layout.

The map requires a general-reader scrolling tour, `/docs`, real app screenshots, one Download for Mac goal, and system light/dark. Review full-page PNGs for those requirements; screenshot tests do not enforce the audience or copy rules.[6]

## Command contract

| Command | Meaning |
| --- | --- |
| `./site-shots.sh` | Render a fresh review set and replace local baselines. Never run automatically to “fix” a failed diff. |
| `./site-shots.sh --diff` | Compare without updating any baseline; nonzero on changed **or missing** images. |
| `SITE_SHOTS_PORT=43933 ./site-shots.sh --diff` | Use another explicit localhost port in a concurrent Rift. |

Proposed paths: `.build/site-shots/<platform>/<project>/<page>.png`, `.build/site-shots-diff/` for expected/actual/diff PNGs and failure traces, `.build/site-shots.log` for all runner/build/server output. Print one summary line on success; on failure add concise errors and artifact/log paths. This follows the existing shell convention, whose app snapshots include deterministic fixtures and explicit states.[7] Deliberate improvement: the site's diff command must fail if a baseline is absent, instead of the app script's `record=missing` behavior. Playwright CLI update modes `all` and `none` implement the distinction (confirmed by the spike).

Keep local images ignored, like the app. In a fresh Rift: capture the starting site **before editing**, then edit and diff. This is a local design loop, not a cross-branch regression gate. If CI gating becomes necessary, separately commit reviewed baselines generated in a pinned CI environment; do not compare macOS baselines with Linux. Playwright warns that OS, browser, hardware, headless mode and other factors affect rendering.[1] A browser-version upgrade is a deliberate baseline review, not a reason to widen tolerance silently.

## Astro integration shape

Move the spike config/spec into `web/tests/` when Astro exists; use the Astro package's pinned `@playwright/test`, committed Bun lockfile, and a root wrapper. First-time setup is `bun install --frozen-lockfile` in that package, then `bun x --no-install playwright install chromium`. The spike uses 1.58.2, an explicit reproducible pin, **not** a claim that it is the latest release.

Have Playwright's `webServer` own `bun run build && bun run preview --host 127.0.0.1 --port "$SITE_SHOTS_PORT"` in `web/`, with matching `baseURL`, `reuseExistingServer: false`, and a bounded SIGTERM teardown. This catches build errors and avoids accidentally photographing another Rift's server. Playwright supports a server command, working directory, readiness URL, output piping and graceful shutdown.[3] Verify the adopted Astro version's preview port behavior; if it silently picks another port, readiness should fail rather than switch target. The current spike binds strictly via Bun instead.

Use an explicit route/state table, not blind link crawling: home, docs, and later meaningful states (open phone menu, open FAQ, each demo step). Assert the route's identifying heading as well as status 200, so fallback HTML cannot pretend to be `/docs`. Add a coverage check against generated HTML routes when the Astro structure is settled. Add separate functional smoke tests for nav/FAQ/download href and Worker compatibility (`/appcast.xml` and release-link updates); screenshots alone cannot prove any of those contracts.[6]

## Determinism and honest coverage

- Set viewport, 1× scale, locale, timezone, and color scheme explicitly.[2] The spike's “phone” means **phone-width Chromium**, not an iPhone/Safari simulator. Add WebKit functional smoke coverage separately if needed; do not multiply screenshot baselines before there is evidence to justify it.
- Wait for the identifying content, `document.fonts.ready`, and image decoding; use locally served fonts/assets. For the future lazy-loaded scrolling page, scroll through sections to load/reveal them, wait for explicit ready conditions, return to the top, then capture. A full-page image does not itself guarantee every lazy asset or scroll-triggered animation ran.[4]
- Use reduced motion plus disabled screenshot animations and hidden caret. Playwright's animation option affects CSS transitions, CSS animations and Web Animations, **not arbitrary application timers**.[4] The current site's own reduced-motion branch calls `app.still()` and skips its animation loop, which made the spike stable without patching production HTML.[8]
- For the redesigned animated demo, keep named deterministic fixture states or use Playwright's clock before navigation and advance to a known state. Clock controls timers and animation-frame APIs; install it before page code uses them.[9] Also exercise normal-motion behavior separately: a still screenshot cannot test animation quality.
- Start with `maxDiffPixels: 0` and default perceptual threshold 0.2. This means no pixels above the perceptual threshold, **not byte-identical comparison**.[4] Do not copy the app's 0.995 image precision as if the two algorithms meant the same thing.
- Review all page/width/theme captures using the agent's local image-reading/preview facility; inspect expected/actual/diff on failure. Full-page shots are required; section crops are optional supplements for small text. No persistent interactive-browser login, production access, or screenshot SaaS is needed.

## Working spike and observed results

Everything executable is isolated in [`site-screenshots/`](site-screenshots/); production HTML, the Worker, and app sources were not changed.

```sh
cd docs/research/site-screenshots
bun install --frozen-lockfile
bun x --no-install playwright install chromium
cd ../../..
./docs/research/site-screenshots/shots.sh
./docs/research/site-screenshots/shots.sh --diff
# Intentional failure, without editing the site:
SITE_SHOTS_MUTATE=1 ./docs/research/site-screenshots/shots.sh --diff
```

Tested on macOS arm64 with Bun 1.4.0, Playwright 1.58.2 and Chromium 145.0.7632.6:

| Experiment | Observed |
| --- | --- |
| Record current `web/public/index.html` | Exit 0; four PNGs, light/dark × desktop/phone. |
| Unchanged diff | Exit 0; four comparisons passed. |
| Inject green `h1` only in the test | Exit 1; all four comparisons failed; expected/actual/diff PNGs and traces produced. |
| Temporarily remove phone-light baseline | Exit 1; missing baseline reported, no baseline written. Restored afterward. |
| Final unchanged diff | Exit 0; all four passed again. |
| `./check.sh` | Failed: 372 tests, 9 skipped, 1 failure in unchanged `CaptureDestinationPanelLayoutTests.testBeginningATextCaptureFocusesTheNoteWithNoScrollInset` (`""` vs `"Follow up"`). No app files changed; cause not investigated. |
| `./ship.sh` | Passed: built, installed and launched. |

Visually inspected phone-light and desktop-dark PNGs: real page, correct respective themes and responsive layout. The current site's full-page PNGs are only viewport-height (390×844 / 1440×1000): its fixed-height desk design clips/scrolls content internally. `fullPage` does **not** unwrap nested scrollers. The spike therefore proves the API and comparisons on today's site, not the future long Astro tour, which does not yet exist. `/docs`, long-page lazy loading, CI portability, Safari, and Cloudflare deployment behavior remain unverified. No reference PNGs are committed; regenerate them locally using the commands above.

## Primary sources

1. [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots): built-in comparison, stable consecutive captures, golden updates, platform variability.
2. [Playwright emulation](https://playwright.dev/docs/emulation): viewport, devices, color scheme, locale and timezone.
3. [Playwright web server](https://playwright.dev/docs/test-webserver): process ownership, readiness, reuse and shutdown options.
4. [Playwright PageAssertions.toHaveScreenshot](https://playwright.dev/docs/api/class-pageassertions#page-assertions-to-have-screenshot-1): full-page, animations, caret, thresholds and comparison semantics. Live docs include newer APIs; the spike uses only APIs verified in its pinned version.
5. [Astro testing guide](https://docs.astro.build/en/guides/testing/): Playwright end-to-end integration.
6. [Map #21](https://github.com/saiashirwad/sendpoint/issues/21), Notes and Destination read before investigation; [ticket #32](https://github.com/saiashirwad/sendpoint/issues/32).
7. Repository [`shots.sh`](../../shots.sh) and [`ScreenshotTests.swift`](../../Tests/SendpointScreenshotTests/ScreenshotTests.swift), especially setup/record mode and `shoot`.
8. Repository [`web/public/index.html`](../../web/public/index.html), `reduced` media query, `play`/`app.still()` and `nudge` timer.
9. [Playwright Clock](https://playwright.dev/docs/clock): timer control and installation ordering.
