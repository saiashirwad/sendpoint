# How comparable products explain themselves on landing pages

Research for [ticket #33](https://github.com/saiashirwad/sendpoint/issues/33), within [map #21](https://github.com/saiashirwad/sendpoint/issues/21). Observed **30 September 2026**. This is a pattern study, not a claim that any pattern improves conversion.

## Recommendation in brief

Use **Lorca's short, one-idea-per-section tour**, **Reader's visible passage-plus-note relationship**, **Granola's chronological explanation**, and **Superwhisper's explicit shortcut cue**. Keep Sendpoint's existing “Think out loud while you read” headline. Make the missing explanation explicit: select a passage, save your thought beside it, then paste the collected notes together. Show this with real app screenshots before asking visitors to watch a demo. Privacy deserves a named section, not just a footer policy. Keep one conversion goal: **Download for Mac**.

Do not copy a broad productivity catalogue, an enterprise logo wall, or a dictation-only promise. Those would obscure what distinguishes Sendpoint from a voice keyboard: collecting thoughts **with their passages** and handing them off together. This recommendation follows the map's general-reader audience and the product's documented loop, rather than competitors' business models. [S0, S1]

## Method and evidence

- Primary sources only: each product's own landing page, plus Raycast and Arc's linked FAQ pages. Section orders below omit navigation/footer boilerplate and collapse responsive duplicates.
- Hero wording is quoted; other observations are paraphrases. Privacy statements below describe **what the page claims**, not independently audited security properties.
- “No homepage FAQ/privacy section” means none was present in the inspected homepage content; it does not mean the product lacks a policy or help centre.
- Screenshots are desktop, light-preference, 1440 × 1000 viewport, 1× scale. `*-hero.jpg` records the initial viewport; `*-full.jpg` records the page after scrolling to trigger lazy loading. These are research references, not licensed assets for the new site. Links below are relative to this file.
- The session's connected browser was unavailable, so screenshots were captured with a separate headless Chromium/Playwright process. No accounts, microphone permissions, sign-ups, or downloads were activated. Dynamic media frames and scroll reveals can differ between captures; screenshots do not prove animation timing or successful playback. In particular, Superwhisper's full-page capture contains substantial empty scroll-animation space and horizontal overflow; use its hero for composition and the cited page text for section order, not the full capture's blank area as an intentional layout recommendation. Cookie banners were left untouched.

## Comparable pages

### 1. Lorca — closest structural reference

**Hero:** “AI teammates for real work.” A paragraph explains one teammate versus group chat, files, commands, memory, and coordination; Download is primary and “See how it works” is an anchor. [S2]

**Order:** hero → Group chats → Privacy → Tools → Getting started → Questions → final Download. [S2]

**Demonstration:** a large real macOS group-chat screenshot accompanies one specific explanation of turn-taking. Privacy uses a simple computer → encrypted relay → phone diagram. Four numbered starting steps cover account, provider, first bot, and another computer. This is a screenshot-and-explanation tour rather than a video-dependent pitch. [S2]

**Privacy framing:** “Runs on your computer,” qualified immediately by the connected provider and encrypted syncing mechanism; the diagram says the relay cannot decrypt. This is a useful model of explaining boundaries instead of asserting “secure.” [S2]

**FAQ topics:** account/server requirement; platforms; model/provider; computer access; chat readership. [S2]

**Borrow:** one heading, one explanation, one piece of evidence per section; getting started and FAQ before a repeated CTA. Do not borrow its agent vocabulary or multi-computer onboarding. The map already selects its sticky frosted pill nav, Inter, zinc greys, rounded cards, and soft borders; retain raspberry rather than copying its accent. [S0]

Screenshots: [hero](landing-patterns/lorca-hero.jpg) · [full page](landing-patterns/lorca-full.jpg).

### 2. Wispr Flow — outcome and transformation before configuration

**Hero:** “Don’t type, just speak.” Supporting text describes speech becoming clear, polished writing in every app; the text response says “Download for free,” while the rendered Mac capture labels the CTA “Get started on macOS.” Supported platforms are immediately stated. [S3]

**Order:** announcement/product navigation → hero with raw/polished writing → professional logos → typing-speed comparison → How it works (speak naturally / edits as you speak / use it anywhere) → personalization capabilities → privacy → testimonials/case studies → FAQ → final two-product CTA. [S3]

**Demonstration:** the page exposes the same rough speech and cleaned-up output in different app contexts, with filler/correction/repetition labels. It makes the transformation legible rather than merely displaying an idle app window. The speed comparison is an advertising claim, not evidence that Sendpoint should make an equivalent numerical promise. [S3]

**Privacy framing:** a named “Your voice stays yours” section: never sold; choice over improvement use; certification badges; a deeper privacy link. Its FAQ repeats the data-control explanation. This is not a local-only claim. [S3]

**FAQ topics:** app compatibility; difference from built-in dictation; languages; accents; fast/quiet/noisy speech; microphones; privacy; free allowance; teams; meeting notetaker; shared subscription. [S3]

**Borrow:** show input and output together; place platform/free status beside the CTA. **Avoid:** replacing Sendpoint's reading story with speed or polished-writing claims, and copying Wispr's growing two-product navigation.

Screenshots: [hero](landing-patterns/wispr-hero.jpg) · [full page](landing-patterns/wispr-full.jpg).

### 3. Superwhisper — teach the gesture and offer a silent path

**Hero:** “Just speak. Write faster.” Supporting text: “Turn your voice into polished text” and compatibility with Slack, Gmail, and other sites/apps. The rendered first viewport shows separate Mac/Windows download buttons; the fetched text exposes “Watch my demo,” a try-it-yourself instruction (choose an app, press ⌥ + Space, dictate), and “Can't talk right now?” as a non-speaking path. The hydrated browser instead showed “Play Demo” / “Scroll to see demo.” This is a delivery/rendering difference, not evidence that both controls are visible simultaneously. [S4]

**Order:** hero/interactive trial → customer proof → adaptability/context examples → capability cards (offline, vocabulary, modes, languages, clipboard, meetings) → custom modes → integrations → agentic coding → mobile promotion → testimonials → pricing → tutorial videos → FAQ/documentation → footer. [S4]

**Demonstration:** a selectable app-context demo plus explicit keyboard gesture, a watch-demo option, and a later video collection (including journaling and messages). The public interface was inspected, not microphone-tested. [S4]

**Privacy framing:** offline operation is a capability card; trust centre and privacy policy appear in the footer. Its Intel-Mac FAQ distinguishes cloud models from offline-model performance on Apple Silicon. Do not simplify this into “all processing is always local.” [S4]

**FAQ topics:** free Pro allowance/free tier and refunds; Intel support; roadmap; using a licence across devices. [S4]

**Borrow:** one visible shortcut in the demo, and a way to understand it without speaking. Sendpoint can use captioned playback and the typed-note alternative instead of implementing a live microphone demo.

Screenshots: [hero](landing-patterns/superwhisper-hero.jpg) · [full page](landing-patterns/superwhisper-full.jpg).

### 4. Granola — explain the workflow chronologically

**Hero:** “The AI notepad for back-to-back meetings.” Supporting lines: “Notes, actions and memory. Without a meeting bot.” Download for free and platform list follow. [S5]

**Order:** hero → “Effortless notes, enhanced instantly” with no-bot/privacy/compatibility reassurance → customer logos → before/during/after meeting tour → meeting memory/chat → testimonials → feature panels → using notes in other tools → free-plan CTA/pricing → footer. [S5]

**Demonstration:** the chronological tour ties each benefit to a moment of use. Later screenshots show the note beside a meeting, sharing controls, mobile notes, and calendar notification. This supplies context and resulting artefacts, not just abstract feature names. [S5]

**Privacy framing:** “Private by default” is early reassurance and a later sharing-control feature. It describes who notes are shared with, not proof of on-device transcription. Security and transparency are deeper footer destinations. [S5]

**FAQ topics:** no dedicated FAQ block observed on this homepage; Help Center and transparency/security links carry deeper explanation. [S5]

**Borrow:** “while you read / keep reading / when you're ready” as a narrative sequence. Do not import meeting-recording language: Sendpoint's microphone is open only while recording a note. [S1]

Screenshots: [hero](landing-patterns/granola-hero.jpg) · [full page](landing-patterns/granola-full.jpg).

### 5. Raycast — useful component references, wrong overall scale

**Hero:** “Your shortcut to everything.” Supporting text identifies a collection of productivity tools in an extendable launcher. [S6]

**Order:** hero → speed/ergonomics/personalization/reliability → extension gallery → agent/AI features → professional testimonials → snippets/quicklinks/hotkeys → wider tool gallery → community/videos → developer API → final download. [S6]

**Demonstration:** keyboard imagery, extension screenshots, a snippet example, shortcut glyphs, and a screenshot carousel demonstrate many individual jobs. It is a catalogue rather than one complete capture-to-output loop. [S6]

**Privacy framing:** not a major homepage section. The separately linked FAQ distinguishes anonymous interaction/error tracking from encrypted local sensitive data, and describes direct third-party extension connections. Treat this as the FAQ's framing, not a comprehensive audit of every AI feature. [S7]

**FAQ topics (separate page):** differences from Spotlight/Alfred; pricing; tracked data; handling data; Windows/Linux; student programme; countries. [S7]

**Borrow:** restrained shortcut glyphs and close-up UI examples. **Avoid:** dense navigation, extension taxonomy, professional/influencer proof, and a developer section for a general-reader single-purpose app.

Screenshots: [hero](landing-patterns/raycast-hero.jpg) · [full page](landing-patterns/raycast-full.jpg).

### 6. Readwise Reader — show the reading object and where notes go

**Hero:** “The first … app for power readers,” with rotating category terms including read-it-later, newsletters, RSS, reading, and web highlighting. Supporting line: “Save everything to one place, highlight like a pro, and replace several apps with Reader.” [S8]

**Order:** hero desktop/mobile UI → supported reading formats → powerful highlighting → Readwise integration/review/remember/sync → testimonials → keyboard/Ghostreader/search/listening capabilities → CTA → flexible reading workflow → integrations → read anywhere → more testimonials → content-overload/triage → FAQ → final CTA. [S8]

**Demonstration:** prominent UI screenshots, especially a document with a highlight and a separate note. Later screenshots connect reading, library organization, and export destinations. This is Sendpoint's closest reference for making the passage–thought relationship visible. [S8]

**Privacy framing:** local-first/offline functionality and data portability appear in product copy and FAQ; the homepage does not lead with a dedicated privacy section. Local-first plus syncing must not be mistaken for local-only. [S8]

**FAQ topics:** price; Reader versus Readwise; devices; read-aloud; importing; exporting/leaving; business longevity after Pocket; assistant integrations; active development. [S8]

**Borrow:** actual readable passages and notes, explicit output destination, and export questions. **Avoid:** suggesting Sendpoint is a reading library, browser replacement, spaced-repetition service, or automatic summarizer. [S1]

Screenshots: [hero](landing-patterns/reader-hero.jpg) · [full page](landing-patterns/reader-full.jpg).

### 7. Arc — calm sectioning, but a changed product context

**Hero context:** the current page first promotes Dia (“Meet Dia, the next evolution of Arc”). The Arc headline is the quoted endorsement “Arc is the Chrome replacement I've been waiting for.” A notice says Arc receives Chromium updates only and directs readers to Dia for active security patches. Do not treat historical Arc screenshots as the present landing page. [S9]

**Order:** Dia promotion → Arc endorsement/downloads/status notice → clean/calm browsing → Spaces and Profiles → setup with Split View/Themes → privacy → testimonials → download. [S9]

**Demonstration:** browser imagery supports one promise at a time: clean workspace, separated contexts, personal setup. The rendered DOM uses autoplay looping videos (`zero-chrome.mp4`, `space-swiping.mp4`, `theme-picker.mp4`) with screenshot/poster alternatives; the Dia promotion also has an autoplay video. This is a motion-led tour, not purely static screenshots. [S9]

**Privacy framing:** “The comfort of privacy”; the page says it does not know visited sites or searches and links to details. The separate FAQ includes data use, monetization, and no-sale assurances. [S9, S10]

**FAQ topics (separate page, explicitly dated May 1, 2024):** differentiation; business model; tracked data; sale of data; Windows/Linux; Chromium; Chrome extensions. Because this FAQ predates the homepage's status notice, it is a pattern reference, not a current roadmap source. [S10]

**Borrow:** one human benefit per screenshot. **Avoid:** testimonial-led category positioning or a second-product CTA; Sendpoint needs its own concrete explanation and one goal.

Screenshots: [hero](landing-patterns/arc-hero.jpg) · [full page](landing-patterns/arc-full.jpg).

### 8. Things — a simple category statement backed by the product

**Hero:** “Things”; the description identifies an “award-winning personal task manager” for planning a day, managing projects, and making progress toward goals. “Watch Introduction Video” is prominent. [S11]

**Order:** hero/introduction video → Simply Powerful / feature link and cross-device screenshots → Get Things / platform purchase cards → user reactions → press/award quotations → newsletter → footer. [S11]

**Demonstration:** an explicit introduction video and large multi-device app imagery, with the deeper feature tour on another page. [S11]

**Privacy framing:** newsletter-specific reassurance (address used only for that newsletter, unsubscribe) and a policy link; no prominent product-data privacy section observed. [S11]

**FAQ topics:** no dedicated FAQ block observed on this homepage. It routes readers to Support and a Getting Productive guide instead. [S11]

**Borrow:** a plain category explanation and genuine app imagery. **Avoid:** requiring a video or a second features page to understand Sendpoint's less familiar workflow; the long award/press section is not suitable without equivalent evidence.

Screenshots: [hero](landing-patterns/things-hero.jpg) · [full page](landing-patterns/things-full.jpg).

## Proposed Sendpoint outline

This is a recommendation for later design/copy tickets, not an implementation or an approved change to the map's open onboarding decision.

| Order | Reader's question | Content and evidence | Pattern source |
|---|---|---|---|
| Sticky pill nav | Where am I / how do I get it? | How it works · Privacy · FAQ · Docs; one primary Download for Mac | Lorca [S2], map [S0] |
| Short hero | What is this for? | “Think out loud while you read.” One explanatory sentence; Download for Mac; “Free · Apple Silicon · macOS 14+”. No animated desk in the hero. | Current promise [S1, S12]; clear category/CTA [S3, S11] |
| Capture | What do I do first? | “Keep the thought with the passage.” Real article/PDF selection beside the recording capsule and saved quote/note; show hold ⌘E and release once. | Reader's annotation image [S8], Superwhisper gesture [S4] |
| Collect | Will I lose my place? | “Keep reading.” Real stack view with two or three thoughts; explain a stack as collected notes, not an organizing system to set up. Mention typing when speaking isn't convenient. | Granola chronology [S5], product [S1] |
| Hand off | What do I get at the end? | “Send the whole train of thought.” Show readable quoted passages plus the visitor's notes in one composed output and its paste destination. Explain paste/copy; don't imply Sendpoint answers questions itself. | Flow input/output [S3], Reader destinations [S8], product [S1] |
| See it work | Can I watch the whole loop? | Move/rebuild the current desk demo here. One captioned select → speak → continue → paste sequence; play/pause/replay and reduced-motion static alternative. Use an article/PDF, not SQLite/terminal content. | Map [S0], current source [S12]; recommendation |
| Privacy | Where do my words go? | Local transcription, notes on this Mac, microphone only while recording, no analytics. Clearly distinguish downloading the model/update checks from exporting into a destination app. | Lorca boundaries [S2], Sendpoint privacy [S1] |
| Getting started | What must I do after downloading? | Brief install/setup overview; link Docs for permissions, model download, troubleshooting, and shortcut reference. Final extent remains an open map decision. | Lorca's numbered start [S2], map [S0] |
| FAQ + final CTA | What could stop me? | Answer concrete objections below; repeat Download for Mac with requirements. GitHub belongs in the footer, not as a competing hero action. | Lorca/Flow/Reader [S2, S3, S8]; recommendation |

### Proposed FAQ priorities

1. **Will it work on my Mac?** Apple Silicon, macOS 14 or later. Put this near Download as well. [S1]
2. **Is it free?** README says free; do not copy competitors' trial/word-limit ambiguity. [S1]
3. **Where do my notes and voice go?** Local transcription/storage; explain model download and signed update checks. Once the visitor pastes into another app, that destination's handling is separate. The latter is a boundary explanation, not a claim that Sendpoint controls other apps. [S1]
4. **Can I type instead?** Yes, ⌘G; leave the complete shortcut list to Docs. [S1]
5. **What gets sent, and where?** Collected notes with passages as Markdown; paste at cursor by default or copy to clipboard; export empties the stack. Explain before users depend on it. [S1]
6. **Is this a reader or a chatbot?** Explain the capture-and-handoff role using the documented loop, without claiming library management or answers. [S1]
7. **What permissions do I need?** Accessibility, Microphone, and the voice-model setup; concise answer with a troubleshooting link. [S1]

**Must verify before publishing copy:** exact language coverage, model-download size, behavior with scanned PDFs, selection capture across specific readers, and installation warnings for the currently shipped signing method. README notes ad-hoc builds may require Privacy & Security → Open Anyway; do not promise a frictionless standard installer without checking the actual release. [S1] None of the competitor pages establishes Sendpoint compatibility.

### Copy corrections and their tone rules

These are proposed replacements, not edits to the current website:

| Avoid | Prefer | Named tone rule |
|---|---|---|
| “Let the AI understand your context.” | “Keep each thought beside the passage that prompted it.” | **Reader agency:** make the reader the subject; describe their action rather than personifying a service. |
| “Supercharge your reading workflow.” | “Select a passage. Hold ⌘E and say what you're thinking.” | **Concrete verbs over hype:** teach an observable action. |
| “100% private. Nothing ever leaves your Mac.” | “Your notes stay on this Mac until you choose to paste or copy them elsewhere.” Add the model-download/update-check explanation nearby. | **Bounded claims:** name the boundary and exceptions rather than promising an absolute. |
| “Capture, contextualize, synthesize.” | “Say it now. Keep reading. Send your notes together when you're ready.” | **Plain language and chronology:** describe the reader's sequence without specialist terms. |
| “Works with everything.” | Demonstrate a verified article/PDF example; document tested capture limits. | **Evidence before universality:** show supported behavior, don't infer compatibility. |

## What this research does not establish

No conversion metrics, user testing, mobile/dark-mode audit, accessibility audit, security audit, or end-to-end competitor app trial was performed. Hero demos were inspected as page content, not tested with personal audio. Dynamic website variants may change the exact order or wording later. The proposed section order is a design judgment grounded in the observations above; it should be tested with a general reader who has never heard of a “stack.” Ask them to explain what stays with a note and what happens at export before considering the outline successful.

## Primary sources

- **S0:** [Map #21, destination and Notes](https://github.com/saiashirwad/sendpoint/issues/21), read before research on 2026-09-30.
- **S1:** [Sendpoint README](../../README.md), especially How it works, Privacy, Install, and Development; inspected in this checkout on 2026-09-30.
- **S2:** [Lorca homepage](https://lorca.app/).
- **S3:** [Wispr Flow homepage](https://wisprflow.ai/).
- **S4:** [Superwhisper homepage](https://superwhisper.com/).
- **S5:** [Granola homepage](https://www.granola.ai/).
- **S6:** [Raycast homepage](https://www.raycast.com/).
- **S7:** [Raycast FAQ](https://www.raycast.com/faq).
- **S8:** [Readwise Reader homepage](https://readwise.io/read).
- **S9:** [Arc homepage](https://arc.net/).
- **S10:** [Arc FAQ](https://arc.net/faq), page marked updated May 1, 2024.
- **S11:** [Things homepage](https://culturedcode.com/things/).
- **S12:** [Current Sendpoint website source](../../web/public/index.html), especially hero/CTA at lines 921–934 and animated desk beginning at line 943; inspected in this checkout on 2026-09-30.

All external sources accessed 2026-09-30. Competitor statements and screenshots are attributed research evidence, not endorsements or reusable Sendpoint marketing assets.
