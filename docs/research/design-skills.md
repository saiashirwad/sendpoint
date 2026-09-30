# Published design skills for Sendpoint

Research for [Which published skills would help us design faster, and how must they change for our workflow?](https://github.com/saiashirwad/sendpoint/issues/30), under [Map: Lorca-style sendpoint.app](https://github.com/saiashirwad/sendpoint/issues/21). Inspected 2026-09-30. **Proposal only: no skills, packages, hooks, or design tools were installed or changed.**

## Recommendation

Keep the existing planning and delegation workflow. Adapt a small amount of published design guidance into it rather than install another end-to-end workflow.

1. Fix the local consensus gap first: `grilling` still specifies prose questions, not AskUserQuestion with a preview for every option. Its delegation adaptation is already correct.
2. Use Anthropic's current `frontend-design` as the design-planning reference, with Claude owning the brief and OpenCode owning implementation. It explicitly says the brief wins, so Inter, zinc, rounded cards, and raspberry are legitimate choices, not defects to remove.
3. Adapt Vercel's `web-design-guidelines` into a small delegated review, with local copy rules overriding its Title Case and curly-quote requirements.
4. Reuse the already-installed Interface Craft critique and optional DialKit tuning. Do not install a duplicate. Plain JavaScript support means an Astro prototype need not gain React just for controls.
5. Borrow selected Impeccable audit/clarify guidance, not its entire orchestration, hooks, context database, or mandatory dual-subagent critique. Skip UI UX Pro Max's design-system generator for this already-directed redesign.

**No candidate merits an unchanged install for this map.** “Adapt” below means a proposed, separately approved change, not something done in this research. “Skip” means no addition for this effort, not that the skill has no value elsewhere. These are judgments about fit, not measured speed improvements.

## Binding context

The map's Notes specify general readers, including students, writers, and researchers; one goal, **Download for Mac**; article/PDF examples; real app screenshots; a short hero; the animated desk demo in its own section; full-page mockups; Inter + zinc + raspberry and system light/dark on the site. The app keeps Geist + raspberry. The destination is Astro served by the existing Cloudflare Worker. Preserve the appcast URL and `release.sh`'s download-link update. Copy must not say “the AI”; make the reader the subject and name the tone rule behind each correction. These are supplied constraints, not conclusions from inspecting Lorca's implementation. [Map Notes](https://github.com/saiashirwad/sendpoint/issues/21)

Every proposed adaptation should inherit those constraints rather than ask the user to decide them again. The homepage and `/docs` have different jobs: explain enough to choose a download versus help someone understand and use the app. Impeccable's current Persuade/Read distinction is useful terminology for this difference, without requiring its file system. [I]

## Local audit and upstream differences

I read every `SKILL.md` found by a symlink-following walk of `~/.claude/skills` and `~/.agents/skills`: **43 paths, 28 unique resolved files**. Fifteen shared skills resolve to the same files through both roots, rather than being independent copies to update twice. I also read all seven delegate scripts: `await`, `finish`, `followup`, `jobs`, `land`, `lib.sh`, and `spawn`. Local sources are machine-local and not published with this report; the inventory below records their content fingerprints.

### What the current workflow actually does

- `delegate/SKILL.md` keeps planning, judgment, explicitly requested Claude code, and quick commands with Claude. Other work goes through OpenCode in Herdr. Writing jobs use Rifts, which include uncommitted work. `spawn` appends “Work alone: no subagents,” no chat questions, a TL;DR-first report, and DONE/BLOCKED contracts. A worker must not import an upstream skill's subagent instructions unchanged.
- `await` distinguishes done, blocked, stalled, timed-out, and hung work, and checks pending permissions/forms. `followup` re-arms completion markers. `land` imports a branch without merging it. `finish` removes the Rift after merge, push, or discard and leaves branches and the tab alone. New skills should call these scripts, not reproduce their git/API mechanics.
- `prototype` already splits logic demos from UI variants and delegates the build. `prototype/UI.md` gives three structurally different variants, a shareable query parameter, a floating switcher, and a production guard. It does **not** yet require a full-page, desktop/mobile, light/dark preview set. Its cleanup section still says to fold a winner into real code, which needs an explicit implementation-authorization gate.
- `grilling` works the available decisions in rounds and preserves human decisions. Its question template is still a prose/emoji block. That conflicts with this map's explicit structured-question and preview requirement.
- `documentation-brief` is already evidence-first and annotation-ready, with Confirmed/Observed/Proposed/Unresolved labels. `unslop` already supplies stable tone-rule numbers, plain language, sentence case, straight quotes, and full sentences. Avoid replacing either with a larger generic copy workflow.
- `interface-craft` is installed and explicitly invoked only. It routes to storyboard, DialKit 2.0, timeline, and critique references. Its critique distinguishes screenshot evidence from code inference, but its “no hedging” and user-emotion language need an evidence/assumption distinction.

Sources for the above: the named local files, inventoried below, plus `~/.agents/skills/prototype/UI.md` and `~/.agents/skills/interface-craft/design-critique.md`.

### Matt Pocock: retain the adaptations, do not wholesale sync

The official repository is [mattpocock/skills](https://github.com/mattpocock/skills), not a marketplace mirror. I compared the following current files at revision `d81f3a183412e71a5b1e84ca21bc1a35eea03a60` against local files. [M]

| Candidate | Observed difference / what it adds | Verdict and exact proposed edit |
|---|---|---|
| `grilling` | Both are 28 lines. The substantive local change replaces upstream's subagent lookup with `delegate`; the round/question format is otherwise retained. | **Adapt local.** Keep frontier rounds and human confirmation. Replace “Format a round like so” and its example with structured AskUserQuestion instructions. Show labeled previews before calling the tool; every option gets a one-line explanation and concrete example, with a recommendation marked. If the tool limits questions per call, split only the already-ready frontier into batches. Never guess downstream answers. |
| `prototype` | Both are 26 lines. Local adds Claude/OpenCode ownership and replaces upstream's immediate “fold into real code” capture rule with a pushed prototype branch. `UI.md` matches the inspected upstream text. | **Adapt local.** Add a preview deliverable to `UI.md`: complete-page variant URLs and screenshots, identical content and fixed brand constraints across alternatives. Add desktop/mobile and light/dark coverage and reduced-motion behavior. Replace automatic promotion in `UI.md` §6 with “record the user's verdict, then delegate production work only when explicitly requested.” Keep the throwaway branch. |
| `domain-modeling` | Both are 74 lines. Current upstream uses `GLOSSARY.md`, `GLOSSARY-MAP.md`, and `GLOSSARY-FORMAT.md`; local uses `CONTEXT` equivalents. The glossary-only discipline and ADR tests match. | **Adapt selectively.** Do not rename local context files just to match upstream. Add structured choices with concrete term/scenario examples when a decision is needed. Have Claude settle terminology; delegate repository edits unless the user explicitly asks Claude to write them. Keep visual tokens out of the domain glossary. |
| `wayfinder` | Local is 68 lines versus upstream's 128. Upstream now abstracts the issue tracker and defaults to local Markdown absent setup; local intentionally uses GitHub and `gh`, with a delegate research brief. | **Adapt local.** Keep GitHub, short instructions, claim-before-work, and one ticket per session. Add “fetch the latest map immediately before patching only the target section, preserve all other bytes, read back afterward; retry from the new body on detected drift.” Put repeated issue-update mechanics in a script. Do not import tracker setup or subagent execution. |
| `to-questionnaire` | Produces an async discovery questionnaire for someone who knows facts the user does not. It asks who receives it and what must come back. Not present locally. | **Skip for this map.** No external stakeholder has been identified. If later needed, adapt questions to labeled previews and concrete examples, and delegate the file write. Do not add another interview before the existing grilling flow. |

These comparisons are against current upstream, not a claim about the local files' original commit or complete historical ancestry. [M]

## Published design/UI candidates

| Candidate and evidence | What it adds beyond local skills | Verdict and concrete adaptation |
|---|---|---|
| Anthropic `frontend-design` [A1] | Subject-specific direction; compact color/type/layout/principles plan; plan review before build; real content; restraint; screenshot self-critique; responsive/focus/reduced-motion quality floor. Unlike older versions often quoted online, this revision explicitly lets the brief override generic-design warnings. | **Adapt, first priority.** Keep its design reasoning as an on-demand reference. Replace its “start to write the code” step with a `delegate` brief. Put fixed map constraints at the top of the brief, not in the reusable skill. Claude shows full-page options and asks structured questions; OpenCode builds the approved direction. Keep a small entry skill, with plan/checklist details in references and rendering mechanics in scripts. Do not invent claims or replace real app screenshots with generated UI. |
| Anthropic `web-artifacts-builder` [A2] | Initializes React/TypeScript/Vite, Tailwind/shadcn and bundles a self-contained HTML artifact. | **Skip.** The site target is Astro, and local `prototype` already covers runnable variants and single-file logic demos. Upstream explicitly discourages Inter and makes visual testing optional; both are wrong defaults here. A future standalone complex React artifact would need delegation, brand overrides, and render-before-handoff, not the unmodified skill. |
| Anthropic `webapp-testing` [A3] | Playwright reconnaissance and a `with_server.py` lifecycle helper. Local browser skills describe interaction/permissions, not a repeatable page-capture matrix. | **Adapt as mechanics, not another top-level design workflow.** Put server start/stop, viewport/theme captures, console errors, and expected output paths in a delegated script. Prefer an existing project browser tool when suitable. Replace blanket `networkidle` waits with explicit readiness/font/image checks appropriate to the page; report timeouts rather than claim a visual pass. Capture all variants, not just components. |
| Anthropic `brand-guidelines` [A4] | Anthropic's own colors and Poppins/Lora typography. | **Skip.** It is not a generic brand-system skill. No edits needed because it should not enter this workflow; preserve Sendpoint's agreed palette/type instead. |
| Anthropic `theme-factory` [A5] | Shows a visual theme catalogue and waits for a choice before applying it. | **Skip the catalogue; borrow preview-before-choice into `grilling`.** Fonts and palette are already decided. Replacing its ten themes with Sendpoint would duplicate the map's constraints. |
| Anthropic `canvas-design` [A6] | A design philosophy followed by static PNG/PDF art. | **Skip for the scrolling site.** It does not test responsive layout, keyboard behavior, or Astro integration. Revisit only if an OG/social-image ticket explicitly needs static art; preserve brand and actual product truth, remove unconstrained font downloads and invented artistic direction. |
| Anthropic `doc-coauthoring` [A7] | Reader testing with a fresh context, after staged context gathering and section editing. | **Adapt only the reader test for `/docs`.** Keep local `documentation-brief` rather than the long interview and 5–20 options per section. Delegate a cold-reader review with only the draft and concrete tasks, such as “How do I collect an article excerpt and add a note?” Report where the text failed; do not treat a model as proof of real-reader comprehension. |
| Impeccable 4.4.0 [I, I1–I3] | Separate Persuade/Operate/Read/Experience modes; targeted audit, clarify, and polish playbooks; bounded visual inspection; detector-backed evidence. | **Adapt selected references, not a full install.** Reuse audit dimensions and clarify's outcome-based writing. Map product context to the map/brief instead of automatically creating PRODUCT.md, DESIGN.md, sidecars, and surface briefs. Remove mandatory subagents, binary launcher/download, overlay injection, hooks, automatic persistence, and numeric health-score ceremony from the local wrapper. Delegate evidence collection; Claude synthesizes and asks. If independent reviews are useful, Claude may spawn two separate delegate jobs, never nested worker subagents. Keep detector findings distinct from taste, and do not require a detector that has not been reviewed/approved. |
| Josh Puckett's Interface Craft / DialKit [J, J1; local files] | Already supplies concrete critique, readable animation storyboards, and live tuning. Current official DialKit has vanilla JS as well as React/Solid/Svelte/Vue adapters. | **Adapt existing local copy; no duplicate install.** Add ownership/delegation routing and preview-based choices. For Astro prefer existing CSS/JS; use the vanilla adapter only when interactive tuning answers a specific question. Keep controls prototype-only, capture chosen values, remove sampled timeline bindings and controls for production. Vanilla controls are enabled by default, so do not assume a React-style production guard protects them. Require a still/reduced-motion alternative and limit motion work to the demo section unless separately agreed. |
| Vercel `web-design-guidelines` [V, V1] | A tiny review entry point plus actionable semantic HTML, focus, images, motion, responsive and theme checks. | **Adapt, first priority.** Delegate read-only audits with `file:line`, rule, evidence, impact, and proposed fix. Snapshot/link the exact guideline revision used, rather than treating a mutable URL as a stable standard. Replace Title Case and curly-quote rules with local sentence case and straight quotes; replace “sacrifice grammar” with complete short sentences. Translate React-specific examples to Astro/HTML only where applicable; do not add handlers to native buttons unnecessarily or add React URL-state libraries. Require browser evidence for behavior that source alone cannot prove. |
| UI UX Pro Max [U] | Searchable style/palette/type/UX data, explicit Astro stack support, and a generated design-system workflow. Current code detects stack rather than blindly defaulting to Tailwind. | **Skip for this map.** The mandatory new-page design-system generation reopens settled choices and adds another MASTER.md hierarchy. If a future project lacks a direction, adapt by disabling mandatory generation/persistence when a brief exists, using explicit `--stack astro` or focused UX searches, resolving scripts from the actual skill directory rather than assuming `CLAUDE_PLUGIN_ROOT`, and delegating execution. Search matches are recommendations, not authority over the brief. |

I selected the additional projects for first-party provenance, concrete scope, and adoption signals, not a claim that stars establish quality. GitHub's API reported approximately 72.8k stars for Impeccable, 131.8k for UI UX Pro Max, and 31.7k for Vercel agent-skills at inspection. These counts are volatile. Interface Craft's official site identifies the author and library; the local copy is available to inspect, but I could not establish its exact current public upstream skill revision. A guessed `joshpuckett/interface-craft` GitHub repository returned 404. Marketplace copies are not authoritative updates. [I, U, V, J]

## Proposed minimal workflow

### 1. One brief, not competing context systems

Claude reads the map and writes a self-contained delegate brief containing the open question, fixed constraints, allowed variation, real content/assets, and proof required. Record missing assets as missing. Do not create generic design-system files just because a third-party skill expects them.

For this map, vary only unresolved layout/teaching choices inside the agreed Lorca-style tour. Do not reinterpret “radically different” as permission to replace Inter, change the accent, target developers, or move the desk demo back into the hero. For `/docs`, vary navigation and explanation structure, not product facts. [Map Notes; M prototype; A1]

### 2. Previews before consensus

Proposed replacement instruction for the question-format block in local `grilling/SKILL.md`:

> Ask ready decisions with AskUserQuestion. Before calling it, show a labeled preview for every option. A visual choice needs the complete page, not an isolated card. A copy choice needs exact proposed words. A behavior choice needs a concrete scenario or walkthrough. Each option description contains one sentence explaining the tradeoff and one concrete example; mark the recommended option. Wait for the user's answer. If no preview is available, delegate its creation before asking the visual question.

Example for an unresolved layout decision, **not a proposed new brand**:

- **A: Paired sections.** Full-page A preview, then “Alternate explanations and real app screenshots so each idea has proof beside it. Example: an article excerpt sits next to its note.”
- **B: Wide screenshots.** Full-page B preview, then “Use a short explanation above each wide screenshot to make details easier to read. Example: show the full stack after the collection step.”

Those previews must actually exist before the live question. Do not offer imaginary screenshot links. An AFK worker returns options and evidence to Claude, never asks the absent user or chooses on their behalf.

### 3. Build, inspect, then ask

Delegate the UI prototype on `prototype/<slug>`. Return one run command, variant URLs, complete-page captures for desktop/mobile and light/dark, the decision each variant tests, and known defects. “Skip polish” means no production architecture or test suite for a throwaway experiment; it does not mean skip checking whether the experiment renders. Browser/server lifecycle and naming belong in scripts. Local `prototype` remains the sole prototype workflow. [Local prototype/UI.md; A3]

Claude uses existing Interface Craft critique plus selected audit rules to compare the variants. Every finding states observed evidence, likely impact, and a proposed change. Label inferred emotions or comprehension issues as hypotheses, not measured outcomes. Each copy correction names its rule, for example `unslop 27: say what it does`, `unslop 29: active voice`, or `Map Notes: reader as subject`. Never claim accessibility compliance from a screenshot alone.

### 4. Separate selection from implementation

Save the human's verdict and link the prototype from its ticket. A selected direction is not permission to merge throwaway code. Delegate production work only after the user requests it. Verify appcast/download behavior as part of that production task, not by installing a design skill. Keep existing `delegate` land/verification/finish semantics. [Local delegate; M prototype; Map Notes]

## Proposed edits and acceptance checks

No edits in this list were applied.

| Order | File or resource to change later | Acceptance check |
|---|---|---|
| 1 | `~/.agents/skills/grilling/SKILL.md` question block | Every option has a real preview, one-line explanation, and concrete example; the structured tool is used; no decision is answered by a worker. |
| 2 | `~/.agents/skills/prototype/UI.md` handover and cleanup; `prototype/SKILL.md` visual-check clarification | A single brief produces complete page variants with fixed brand/content, desktop/mobile light/dark captures, and no unsolicited production promotion. |
| 3 | A short local design reference entry derived from A1, with source revision and changes recorded | Claude produces a scoped brief; an OpenCode Rift builds it; Inter/zinc/raspberry survive. No copied subagent or React scaffold instruction fires. |
| 4 | A short delegated web review reference from V/V1 and selected I2/I3; capture/server script | Findings include reproducible evidence, not only scores. Sentence case/straight quotes survive. Reduced motion and keyboard focus are exercised, not inferred from static images. |
| 5 | Existing `interface-craft` routing and critique reference | A screenshot critique stays separate from implementation, marks inference honestly, and does not add a React dependency for Astro tuning. |
| 6 | `wayfinder` latest-body update instruction and a narrow patch helper | An unrelated new map decision inserted before the write is preserved; the helper is idempotent for the same ticket and verifies the final body. GitHub body updates are not assumed to be transactional across sessions. |

Before adopting adaptations, compare baseline versus adapted behavior on three briefs: the homepage tour, `/docs` reader comprehension, and the separate animated demo. Measure elapsed time, revision count, constraint violations, missing previews, and unexpected dependencies. Human preference chooses visual quality. The existing skill-creator offers baseline/evaluation structure, but its own nested subagent mechanics also need delegation adaptation; do not auto-install or rewrite skills as part of this survey. [Local skill-creator]

## Coverage and limitations

- All 28 unique local `SKILL.md` files were read. The seven delegate scripts and the two specifically cited UI/critique references were also read. This is not a claim to have read every local reference, asset, or script in every skill.
- The local synced document/browser/computer skills are tool/output-specific. They remain relevant when those tools or formats are requested, but are not replacements for the design/consensus pipeline. `deep-research` conflicts with the no-subagent worker contract, so this task followed the delegated `research` procedure instead.
- No candidate was installed or executed. No live design benchmark, detector accuracy test, skill-trigger test, or Astro integration test was performed. The speed/fit recommendations are qualitative.
- Astro is the map's destination. `web/package.json` was absent in this checkout at inspection; this report does not claim the migration already exists or prescribe a current web task-runner command.
- No protected Interface Craft member content was accessed. Its local installed skill and official public DialKit documentation support the recommendations, but not an assertion that the local skill is the newest distribution.
- Before copying any third-party material, inspect its pinned license and retain required notices. This report links and analyzes sources; it does not vendor their content or establish redistribution rights for the synced proprietary skills.

## Local source inventory

SHA-256 prefixes identify the bytes read, not a promise that these machine-local paths remain unchanged. Shared entries are accessible at both `~/.agents/skills/<name>/SKILL.md` and `~/.claude/skills/<name>/SKILL.md`. The synced entries live below `~/.claude/skills/synced/01ab1ca0-cab0-4256-ab7f-e2e4a1f8997b_05897013-addf-4720-a725-722d564c9392/<name>/SKILL.md`.

| Shared skill | SHA-256 prefix | Role in this survey |
|---|---|---|
| research | c675f46d6e5b | Primary-source report contract |
| domain-modeling | 327a2b50620e | Terms and ADRs |
| wayfinder | e83e1aa15218 | GitHub decision map |
| handoff | 028707c18096 | Explicit temporary handoff |
| what-did-i-get-done | 592a1c6c7dc1 | Commit summary, outside design scope |
| ideation | d83ebb0ce632 | Explicit, one-question-at-a-time discovery; not a replacement for map grilling |
| delegate | 682c096552af | Ownership, Rifts, completion |
| prototype | 0082ea64c568 | Logic/UI experiment routing |
| herdr | d55fb9e60145 | Existing agent/pane operations |
| tandem | 710c3bc1ea73 | Source-anchored reviews; approval alone is not implementation |
| zoom-out | 5d894456d761 | Evidence-backed code orientation |
| documentation-brief | 6b2b2ce3d967 | Editorial decisions before drafting |
| interface-craft | 7ef0198984f8 | Existing critique and motion toolkit |
| unslop | a150242f6f7d | Named tone rules |
| grilling | 9938ea826f73 | Frontier consensus |

| Synced skill | SHA-256 prefix | Relevance |
|---|---|---|
| morning | a7c4dbcb7457 | Explicit daily brief only, not a site theme |
| deep-research | 46ae8d5a0b95 | Subagent coordinator, not this worker's research path |
| xlsx | 6712b39718fe | Spreadsheet output |
| pdf | 9f78b8359fbd | PDF processing |
| import-memory | 5179b0780b70 | Memory import only |
| docs | 98e4fb593404 | Dedicated document connector |
| skill-creator | 42765c880e44 | Evaluation concepts, adapt execution later |
| pptx | 6c20f2928ca8 | PowerPoint output |
| google-workspace | f53b2d8c9bcb | Google file editing |
| chrome-browser | c8b0afeee246 | Browser permissions and real-tab safety |
| built-in-browser | b5a720afbcde | Browser-pane mechanics and limitations |
| computer-use | bc4b958fd640 | Desktop tool boundaries |
| docx | 912cb15683a4 | Word output |

## Published primary sources

All GitHub skill links below are pinned to the revision read. Search/marketplace results were discovery aids only.

- **[M]** [Matt Pocock repository at inspected revision](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60): [grilling](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/grilling/SKILL.md), [prototype](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/prototype/SKILL.md), [UI reference](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/prototype/UI.md), [domain-modeling](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/domain-modeling/SKILL.md), [wayfinder](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/wayfinder/SKILL.md), [to-questionnaire](https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/productivity/to-questionnaire/SKILL.md).
- **[A1]** [Anthropic frontend-design](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/frontend-design/SKILL.md).
- **[A2]** [Anthropic web-artifacts-builder](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/web-artifacts-builder/SKILL.md).
- **[A3]** [Anthropic webapp-testing](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/webapp-testing/SKILL.md).
- **[A4]** [Anthropic brand-guidelines](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/brand-guidelines/SKILL.md).
- **[A5]** [Anthropic theme-factory](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/theme-factory/SKILL.md).
- **[A6]** [Anthropic canvas-design](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/canvas-design/SKILL.md).
- **[A7]** [Anthropic doc-coauthoring](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/doc-coauthoring/SKILL.md).
- **[I]** [Impeccable skill 4.4.0](https://github.com/pbakaus/impeccable/blob/0d6b47ea19b63afe15e3f93a44d5d9fbbc6fd275/.agents/skills/impeccable/SKILL.md).
- **[I1]** [Impeccable critique](https://github.com/pbakaus/impeccable/blob/0d6b47ea19b63afe15e3f93a44d5d9fbbc6fd275/.agents/skills/impeccable/reference/critique.md).
- **[I2]** [Impeccable audit](https://github.com/pbakaus/impeccable/blob/0d6b47ea19b63afe15e3f93a44d5d9fbbc6fd275/.agents/skills/impeccable/reference/audit.md).
- **[I3]** [Impeccable clarify](https://github.com/pbakaus/impeccable/blob/0d6b47ea19b63afe15e3f93a44d5d9fbbc6fd275/.agents/skills/impeccable/reference/clarify.md).
- **[J]** [Official Interface Craft library](https://www.interfacecraft.dev/) and [author's site](https://joshpuckett.me/). Public pages inspected; no authenticated library content accessed.
- **[J1]** [Official DialKit README](https://github.com/joshpuckett/dialkit/blob/0301abdf0b84fc3d60a4c4fa3a99bfb2044959e3/README.md), revision resolved after reading the live source on 2026-09-30. Covers adapters, vanilla production visibility, teardown, and replacing sampled timeline values.
- **[V]** [Vercel web-design-guidelines skill](https://github.com/vercel-labs/agent-skills/blob/063bee94c3f4df8453406c830b0a7df0f2860278/skills/web-design-guidelines/SKILL.md).
- **[V1]** [Vercel guideline rules](https://github.com/vercel-labs/web-interface-guidelines/blob/e3d624baaf29dc1fc645aff3e38f03e564d2d6b1/command.md), revision resolved immediately after fetching the live rules.
- **[U]** [UI UX Pro Max skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/09170eec67eefd46a7ae85de61b40c194020f997/.claude/skills/ui-ux-pro-max/SKILL.md).
