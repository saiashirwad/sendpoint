# Design convergence for sendpoint.app

Research for [ticket #31](https://github.com/saiashirwad/sendpoint/issues/31), in [map #21](https://github.com/saiashirwad/sendpoint/issues/21). Researched 2026-09-30.

## Recommendation

**Use three full-page, structurally different browser variants, a screenshot comparison sheet, and one explicit decision record.** Keep the existing `?variant=` switcher as the interactive surface; add side-by-side evidence so the user need not remember the previous page. Use an Astro dev server once the Astro shell exists. Claude Artifacts are an optional asynchronous review wrapper, not a second implementation. Pencil or a Figma-like canvas is an escape hatch for direct visual exploration, not a mandatory stage.

This is a reasoned recommendation for this map, **not a measured claim that one tool universally converges fastest**. The main optimization is to eliminate translation and ambiguous feedback: one question, visible alternatives, one named version, one recorded verdict. The current prototype skill already supplies much of that loop.[2]

Do not reopen the fixed brief: general readers; articles/PDFs rather than terminals; Download for Mac as the goal; Lorca-style scrolling tour plus `/docs`; Inter, zinc, raspberry; system light/dark; real app screenshots; the animated demonstration below the hero. Full-page mockups are required. Those constraints come from the map, not this research.[1]

## Comparison: what to hand over

Times below are **planning estimates**, not benchmarks: one agent, existing content/assets, no new authentication, no production hardening. “Incremental” means the full-page alternatives already exist. First-time tool setup can dominate any estimate. Feedback and capture columns describe the proposed workflow, not automatic integrations.

| Primitive | Estimated production time | How the user responds | How the decision is captured | Fit here |
| --- | --- | --- | --- | --- |
| Style tiles | 15–30 min for a small set | Chooses type, color, surface treatment | Named tile + accepted token values + rationale | Optional only if the fixed style is challenged. Tiles intentionally omit layout, so cannot approve this scrolling tour.[3] |
| URL-param variant switcher | 45–120 min for 3 full-page options; 10–20 min to wire the bar | Flips A/B/C, scrolls, tries nav/FAQ; names parts to keep | Commit + URL + variant + section-level keep/change list | **Primary.** Matches the current skill; preserve its three-variant default and structural differences.[2] |
| Side-by-side full-page screenshot grid | 10–20 min incremental | Compares section rhythm and hierarchy simultaneously | Versioned images, viewport/theme labels, numbered observations | **Required companion.** Link each thumbnail to its readable full-resolution capture; a tiny long-page grid alone cannot judge copy. Static evidence does not validate interactions. |
| Annotated screenshots | 5–15 min incremental | Circles or numbers a region and explains the problem | Original capture + annotations + issue checklist | **Best precise correction channel.** Example: “B / 390px / dark / 02: this screenshot is too small to read.” Can be plain images and issue/chat text; no annotation service required. |
| Claude Artifact, published HTML | 15–30 min incremental packaging; longer if rewritten | Reviews a comparison page; comments where supported | Artifact URL **and version**, source HTML/captures in branch, issue verdict | Optional async delivery. It supports inline HTML/CSS/JS and versioned sharing, but is one page, not an Astro deployment.[4] |
| Pencil `.pen` via MCP | 45–120 min for full-page boards after setup; setup unmeasured | Points to or changes canvas elements; agent iterates | `.pen` checkpoint + exported images + textual decision | Conditional: useful if spatial editing is the bottleneck. Tools are exposed here, but no open file was available for a working trial.[8] |
| Figma-like canvas (Figma as verified example) | 45–120 min after setup | Pins comments to a location/region or edits with permission | File/frame link + frozen export + issue verdict | Good when the user already wants canvas editing. Figma supports pinned/region comments with view access.[5] Do not introduce a parallel canvas solely to recreate browser output. |
| Design tokens file | 10–20 min to record a small accepted set | Reacts to rendered examples, **not raw JSON** | Named CSS values in code; optional DTCG JSON if interchange is actually needed | Output of a decision, not the main review surface. DTCG standardizes token exchange, not page composition.[6] |
| Astro dev server with live updates | 5–10 min to start an existing setup; 30–60 min for a minimal first shell | Reviews real responsive layout and interaction, then sees edits | Source commit + run command + captures/verdict | **Primary rendering engine**, complementary to the switcher. Astro updates the browser when source files change; a running localhost URL is not a durable/shared artifact.[7] |

The screenshot rows are workflow proposals; no native screenshot-comment synchronization is assumed. The canvas estimates include drawing full pages, not just a hero.

## Important tool distinctions

### Variant switcher: retain it, make comparisons reproducible

The local skill prefers adapting an existing route, uses three radically different variants (maximum five), a fixed bottom bar, arrow-key cycling, shareable `?variant=` values, no mutations, and a throwaway branch. It requires archiving the alternatives and verdict, then properly implementing only the winner.[2]

For this map, “radically different” means different hierarchy **within the agreed direction**, not three unrelated brands. Example hypotheses: A explains the reading workflow in successive steps; B leads with a large annotated app screenshot; C alternates article/PDF examples with the resulting notes. Each still has the complete tour, real assets, the same primary goal, and the fixed palette. If the ticket concerns only one section, keep the rest of the full page identical to isolate that question.

Proposed additions:

- Label each variant with its hypothesis and one tradeoff, not just A/B/C.
- Display a revision ID; record source commit, route, viewport, theme, and section in feedback.
- Preserve the section anchor when switching, or provide explicit “compare this section” links.
- Hide the switcher for captures; never let it cover the footer or CTA being judged.
- Provide a desktop full-page comparison first, plus mobile and dark-mode captures for each option. Do not present twelve unlabeled thumbnails at once.
- Keep theme overrides preview-only; production follows the system. Freeze animation for comparison captures, then review the demo in motion separately.

**Astro caveat:** do not blindly paste the skill's React-like pseudocode into a statically generated `.astro` page. For a static prototype, read `window.location.search` in a small browser script and select the rendered variant; server-only selection at build time cannot respond to later browser query changes. Alternatively use an explicitly server-rendered prototype. The implementation is still throwaway; no React dependency is necessary solely for this bar.

The skill hides the bar in production builds. Therefore a built remote preview needs an explicit, isolated prototype-only build configuration if it should retain the bar; do not assume a normal production preview will show it. Production must contain neither losing variants nor prototype controls.[2]

### Artifacts: useful review wrapper, qualified commenting

First-party documentation supports a single self-contained HTML page, live updates, version selection, and sharing. It explicitly says that relative links do not resolve and external images are blocked by its CSP; embed screenshots as data URIs and keep the rendered page within 16 MiB. A real home-to-`/docs` navigation test belongs in the site preview, not a simulated Artifact.[4]

Most importantly, **a public Artifact link does not imply commenting access**. The documented comment flow is for organization-shared artifacts; public-link-only viewers cannot see or add comments. Reading comments requires the documented Claude Code version/account conditions. OpenCode should not be assumed to inherit Claude Code's publish/comment tools. The brief says Artifacts are available in the parent workflow; this session did not publish one or verify the user's exact sharing entitlement.[4][8]

Use an Artifact when the parent session can publish it and the reviewer has appropriate access. Show the same screenshots/labels as the browser preview rather than building another divergent page. If comments are unavailable, accept numbered feedback in chat or the issue. Always copy the accepted verdict into the ticket; a mutable page or comment thread is not the decision record.

### Pencil, Herdr, and Rifts: roles, not interchangeable outputs

The exposed Pencil MCP advertises `.pen` editing, app state, styles, and browser import/screenshot actions. Its `.pen` files must be accessed through MCP rather than as plain text. Both `read_skill` and `get_app_state` failed in this session because no file was open. Consequently this report does **not** claim tested comment support, export fidelity, code generation, or Astro round-tripping. Open a document and read the tool's skill/schema before any future design trial.[8]

The local delegation workflow uses Herdr tabs for agent sessions and a Rift for an isolated copy of the checkout, including uncommitted work. It lands the branch for review rather than merging automatically.[9] These are production/isolation aids, not user-facing design evidence. Give agents the same brief and have one owner assemble the review packet; avoid asking the user to reconstruct alternatives across multiple terminal tabs. Do not assume a Rift also isolates shared services, app installation paths, or network ports.

### The checkout is not yet Astro

At the inspected base commit, `web/wrangler.jsonc` points to `src/worker.js` and `public` assets; the `web/src` directory contains the worker rather than Astro pages. `release.sh` knows about `web/public/index.html`, `web/public/appcast.xml`, and `/download`.[10] Treat the Astro server as the intended target workflow, not an already available command. Until the Astro shell lands, a clearly marked static full-page HTML prototype in the existing web structure is sufficient. Do not turn this research ticket into a migration or alter release paths merely to preview options.

## Recommended loop for each prototype ticket

1. **State one decision.** Write the question, fixed constraints, and an observable acceptance criterion in the ticket. Example: “Can a reader tell what to collect and where the notes go before the second section?” Getting-started depth remains a separate open question in the map.[1]
2. **Produce one review packet.** In `prototype/<slug>`, build three full-page alternatives with consistent real copy/assets. Supply the one-command startup, exact variant URLs, labeled screenshot sheet, and full-resolution images. Use the existing route once Astro exists; mark all work as throwaway.[2]
3. **Ask one bounded question with visible options.** Show the previews before asking. Give each option a one-line explanation and concrete example. Ask for a preferred structure, one part to borrow, and the largest confusion—not “any thoughts?” Suggested wording: “Which tour makes collecting an article easiest to understand: A's steps, B's annotated screenshot, or C's reading examples?”
4. **Normalize feedback.** Convert each observation into `revision / variant / section / viewport / theme / problem / requested change`. Distinguish a preference from a blocker. For copy corrections, name the rule, e.g. “reader agency: replace a sentence centered on ‘the AI’ with what you do.”[1]
5. **Synthesize, don't endlessly regenerate.** Produce one combined candidate plus the previous leader, with a short change list. Review desktop/mobile, light/dark, readable screenshots, nav/FAQ, and the demo in motion. If none works, revise the hypothesis rather than polish three failing options.
6. **Close the decision explicitly.** Record the accepted variant/combination, why, rejected alternatives, remaining risks, exact commit, captures, and any Artifact version. Update the map with one gist. A sensible target is one selection round and one confirmation round; if that fails, split the question. This target is a proposed budget, not an evidence-backed guarantee.
7. **Promote the decision, not the prototype.** Archive the pushed branch, implement the winner properly, remove prototype controls/losers from production, and verify the real site's routes, system theme, download behavior, and unchanged appcast URL. Accepted values become the small token layer; do not build a token pipeline just for this review.[1][2][6][10]

Suggested verdict template:

```text
Question:
Accepted: revision + variant + borrowed sections
Why (reader outcome):
Rejected / why:
Evidence: commit + URLs + captures (viewport/theme) + Artifact version if used
Copy corrections / tone rules:
Remaining risk or follow-up ticket:
```

## Confidence and unconfirmed points

- High confidence in the documented Astro, Artifact, Figma, and token capabilities cited below; no comparative user study or timing experiment was run.
- Time ranges and the two-round target are estimates. Measure first-preview time, feedback rounds, and implementation rework on the next two prototype tickets before standardizing further.
- Pencil was exposed but not operational without an open file. No `.pen` file or canvas was created.
- No Artifact was published, and no end-to-end comment retrieval was tested. Use the parent session's available publishing tools or fall back to screenshots plus the issue.
- This research makes no claim that screenshots validate accessibility, responsiveness between sampled widths, animation, or production download behavior. Those need browser/implementation checks.

## Sources

All web sources accessed 2026-09-30. Local skills are machine-local primary sources, not files added by this report.

1. [Map #21, Destination and Notes](https://github.com/saiashirwad/sendpoint/issues/21), read with `gh issue view 21 --json body,title,url` before research. Supplies constraints and open questions.
2. Local `~/.claude/skills/prototype/SKILL.md`, lines 8–26; `~/.claude/skills/prototype/UI.md`, lines 14–112. Supplies route preference, structural alternatives, switcher behavior, throwaway lifecycle, and verdict capture.
3. [Style Tiles: What / When / How](https://styletil.es/). Defines fonts/colors/interface elements as visual language without layout. Its speed claims are qualitative; not used as benchmark evidence.
4. [Claude Code: Share session output as artifacts](https://code.claude.com/docs/en/artifacts), especially Collect comments, Page constraints, Availability, and Share. Also [What are artifacts?](https://support.claude.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them) distinguishes current and legacy artifacts. Capabilities here refer to the documented Code HTML-page surface, not every product named Artifact.
5. [Figma: Add comments to files](https://help.figma.com/hc/en-us/articles/360041068574-Add-comments-to-files), prerequisites and Add a comment. Verifies location/region commenting and view-access requirement.
6. [DTCG Format Module 2025.10](https://www.designtokens.org/TR/2025.10/format/), Introduction, Terminology, File format. Stable Community Group specification, not a W3C Standard; use the versioned publication, not the preview draft.
7. [Astro: Develop and build](https://docs.astro.build/en/develop-and-build/), Start the Astro dev server, Work in development mode, Build and preview. Verifies live source updates and the distinction between dev and built previews.
8. Session-local Pencil MCP tool schemas (`pencil.browser`, `get_app_state`, `read_skill`) and calls on 2026-09-30: both state/skill reads returned “A file needs to be open in the editor.” The task brief lists Pencil, Artifacts, Herdr, and Rifts as available workflow options; this is not equivalent to testing them all.
9. Local `~/.claude/skills/delegate/SKILL.md`, lines 8–17 and 27–33. Defines tabs, Rift isolation, branch handoff, and prototype/research report contracts. No agents were spawned for this research.
10. Checkout inspected at [`3288cbac`](https://github.com/saiashirwad/sendpoint/tree/3288cbacb3872f65845636e843319adc203b074c): [`web/wrangler.jsonc`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/web/wrangler.jsonc#L3-L10), [`release.sh`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/release.sh#L239-L249). Current architecture and release invariants, not an Astro implementation.
