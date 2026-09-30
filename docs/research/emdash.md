# EmDash for sendpoint.app: plain Astro now

Research date: 2026-09-30. Resolves [#23](https://github.com/saiashirwad/sendpoint/issues/23) in [map #21](https://github.com/saiashirwad/sendpoint/issues/21). This is a recommendation and integration plan, not a deployed CMS experiment.

## Decision

**Build the redesign with plain, static Astro. Do not adopt EmDash now.** Keep the tour and FAQ in source, use a Markdown page for `/docs`, and add a file-backed Astro content collection when a changelog or blog actually exists. EmDash becomes worthwhile when someone needs browser-based editing, independent publishing, scheduled posts, or multiple editorial roles—not merely because the site gains a docs page. Astro explicitly recommends build-time collections for relatively static docs and blogs, and simple page components for a few pages. [A1]

EmDash is a credible later option, not an incompatible platform: its official Cloudflare deployment uses Workers + D1 + R2 and can retain the `sendpoint` Worker name and custom domain. But it changes a static-site deploy into operating a database-backed application, authenticated admin/API surface, scheduled maintenance, and recoverable content/media storage. Those costs do not advance the current map's download-focused tour and `/docs` goal. [E2][L1][M1]

## What it adds, and whether this site needs it

| Need | Plain Astro proposal | EmDash addition | Assessment |
| --- | --- | --- | --- |
| Tour, getting started, FAQ | Astro components and structured local data | Database-backed fields editable without a code deploy | Low present value; layout and screenshot work still need implementation. |
| `/docs` | Markdown or an Astro page; collection if docs expands | Browser authoring with draft/published separation and revisions | Useful for non-code editors, not necessary for this one page. |
| Future changelog/blog | Markdown collection with title, date, version/slug; build to publish | Scheduled publishing, draft comparison, revisions, bylines and taxonomy management | Revisit when editorial cadence or collaborators make deploys a bottleneck. |
| Agent-assisted maintenance | An agent edits repository files and reviews a diff | Authenticated MCP endpoint can manage live content, schema, media and settings | Convenient, but adds production credentials and write permissions; not required for agent-authored copy. |
| Media | Versioned local screenshots/assets | Uploadable R2 media library and runtime image transformation | Useful for frequent editorial uploads; unnecessary for a handful of release-controlled screenshots. |

The capability column is grounded in the integration, MCP and Cloudflare docs; the value judgments are recommendations for the scope in map #21, not claims about measured editor demand. EmDash's MCP is at `/_emdash/api/mcp`, uses bearer tokens (OAuth or personal tokens), enforces roles and scopes separately, and supports revision checks to reject stale writes. Prefer narrowly scoped content access rather than `admin` if adopted. [E2][E3][E4][M1]

EmDash 1.0 was announced on September 28, 2026, two days before this research. The project describes it as stable, MIT-licensed and production-proven. That is first-party evidence of release status, not our own reliability benchmark; this recommendation is about fit, not a claim that EmDash is unstable. [E1]

## Existing constraints verified in this checkout

Inspected base commit: `3288cbacb3872f65845636e843319adc203b074c`.

- `web/wrangler.jsonc` names Worker `sendpoint`, binds `./public` as `ASSETS`, runs the Worker first, and maps the `sendpoint.app` custom domain. There are no D1/R2 bindings in this file. [L1]
- `web/src/worker.js` returns a **302** for both `/download` and `/download/` to `https://github.com/saiashirwad/sendpoint/releases/latest/download/Sendpoint.dmg`; all other requests go to `env.ASSETS.fetch`. [L2]
- `release.sh` generates/signs `web/public/appcast.xml`, uploads both the versioned DMG and stable `Sendpoint.dmg` to GitHub, and deploys the website with Wrangler in both normal and resume-publish paths. [L3]
- **The download rewrite is already conditional.** `release.sh` checks `web/public/index.html` for `href="/download"`; when found, it skips rewriting the hard-coded versioned link. Otherwise it rewrites and verifies the URL, then stages that page with the version and appcast. Migrating the page to Astro without changing this path/check will break publishing. [L3]
- `web/public/appcast.xml` contains Sparkle update/enclosure signatures and a signed-feed footer. It must remain release-generated, not edited by a CMS or transformed by a page renderer. [L4]

## Recommended plain-Astro deployment and release contract

This is proposed follow-up work, **not implemented by this research**:

1. Make `web/` the Astro project; move the home page into `src/pages/index.astro`, remove the old `public/index.html` as part of that migration, and build static output to `web/dist`. Keep the custom Worker as the `/download` redirect handler, and point its `ASSETS` directory at `./dist` instead of `./public`. Retain Worker name and domain. Astro copies `public/` assets untouched; do not leave two home-page sources. [A1][A2][L1][L2]
2. Keep `web/public/appcast.xml` exactly at its existing source path; it emerges as `/appcast.xml` in static output. Build **after** generating the new signed feed so the deploy cannot contain the previous release's XML. Never route that URL through a CMS catch-all or HTML fallback. [A2][L3][L4]
3. Keep every download CTA pointing at `/download`. Update `release.sh` to validate the new source/build contract, stop staging the removed `public/index.html`, and build before Wrangler deployment in **both** publish branches. Keep stable DMG upload and the redirect's latest-release target; a release still updates what the download link resolves to without a CMS write. [L2][L3]
4. If the map instead requires a literal version-pinned URL on the page, have `release.sh` write a small committed data file imported by Astro, then build. Do not run the current HTML substitution against generated output or store the authoritative release URL only in D1. This is an alternative design, not needed with `/download`. [L3]
5. Add migration checks: built XML byte-equals source XML; `/appcast.xml` returns XML, not a page/login; `/download` and `/download/` still redirect correctly; `/`, `/docs`, assets and unknown paths behave correctly; normal and resume-publish both build the site. Confirm the newly uploaded stable DMG is available before directing users to it. These checks follow the existing contracts above. [L1–L4]

## If choosing EmDash now: concrete integration work

There is no requirement to move off the existing Worker/domain, but **the existing 16-line Worker is not itself the EmDash runtime**. Use the official Cloudflare integration rather than bolting the admin onto static assets. [E2][L2]

1. **Dependencies/config:** use Astro 6+ and Node 22.16+; install `emdash`, `@emdash-cms/cloudflare`, `@astrojs/cloudflare`, `@astrojs/react`, `react` and `react-dom` alongside Astro. Configure `output: "server"`, the Cloudflare adapter, React (required for admin), and `emdash({ database: d1({ binding: "DB" }), storage: r2({ binding: "MEDIA" }) })`. Add `_emdash` in `src/live.config.ts` with `defineLiveCollection` and `emdashLoader`. File-backed collections can coexist. [E2][E3]
2. **Worker/bindings:** preserve `name: "sendpoint"` and the custom-domain route. Adopt the documented `@emdash-cms/cloudflare/worker` handler and `createScheduledHandler()` entry point, `nodejs_compat`, a D1 `DB` binding and R2 `MEDIA` binding. Preserve `/download` as an early redirect or a server endpoint with equivalent behavior. Use the adapter-generated asset/deployment configuration rather than blindly retaining `assets.directory: "./public"`; inspect `.wrangler/deploy/config.json` and its generated target after the build. [E2][L1][L2]
3. **Provisioning/deploy:** the current guide says a first `build` + `wrangler deploy` provisions named D1/R2 resources when missing, and first request applies core migrations in default `auto` mode. Keep resource names stable. For deployment-managed migrations, explicitly provision D1 first, record its UUID, build, inspect `emdash migrate --status`, apply to the reviewed target, deploy that same build and run `emdash migrate --check`. Migration CLI credentials need scoped D1 Edit permission. Do not confuse resource creation with schema migration. [E2][E5]
4. **Setup/content:** finish the setup wizard at `/_emdash/admin/`, create the administrator/passkey and model docs/FAQ/posts; implement public Astro templates that query and render those collections. A CMS integration alone does not implement the Lorca-style design. Subsequent deployments leave an existing database's content alone; changing the seed is not a general mechanism for updating deployed content. [E2][E3]
5. **SSR vs static:** admin/API and live-content pages need a runtime. The supported recipe uses server output; a prerendered page will not show newly published edits until rebuilt. Keep source-owned/static routes independent where appropriate, but do not assume “CMS editing without deploys” works on a fully static export. SSR queries add D1 round trips; the guide recommends targeted placement near D1 and offers optional KV object caching. Public response-cache freshness and invalidation become another decision. [E2][E3][A1]
6. **Scheduled work:** wire the Cron Trigger and scheduled handler for scheduled publishing, backups and maintenance (the template uses every minute). Without sandboxed plugins, omit `sandboxRunner` and `LOADER`; do not adopt plugins, KV, AI Search or email merely because the template can support them. Runtime image transformations use an Images binding and have separate limits/costs. Magic-link email and invitations need an explicitly configured provider; production Workers do not supply email by default. [E2]
7. **Operations/security:** own admin access, least-privilege MCP credentials, dependency upgrades, separate preview D1/R2 resources, and recovery drills. Keep `EMDASH_ENCRYPTION_KEY` as a runtime secret with an independent backup if storing plugin secrets. Never expose the R2 `backups/` prefix through a public bucket domain. [E2][E4][E6]
8. **Release compatibility:** apply the same build-after-appcast and both-publish-path changes described above. Keep appcast and download resolution outside CMS content. Verify feed access without cookies and while CMS/database operations fail; if necessary give `/appcast.xml` an explicit asset bypass so updates are not dependent on CMS initialization. Do not cache a stale feed indefinitely. These are acceptance requirements, not behavior verified in an EmDash deployment. [L2–L4][E2]

### The recovery trap

**EmDash's “Download backup” JSON is not a restorable database backup.** The docs explicitly say there is no JSON restore implementation; it also omits authentication data, plugin state/secrets and media binaries. Use D1 Time Travel or SQL export plus a separate media backup and secret backup; verify them together on a recovery deployment. Core migrations are forward-only: rolling the Worker back does not undo the database migration. This is a substantial operational difference from restoring a static site commit. [E5][E6]

## Cost: money is likely smaller than maintenance

These are published USD rates checked on the research date, **not a bill forecast**. Traffic, current account plan, actual SSR CPU use, storage and shared-account quota consumption were not measured.

| Component | Published allowance / rate | Implication |
| --- | --- | --- |
| EmDash license | MIT/open source [E1] | No CMS license fee; operating it is still work. |
| Workers | Free: 100,000 requests/day, 10 ms CPU/invocation. Paid: $5/account/month minimum, 10M requests and 30M CPU-ms/month included; then $0.30/M requests and $0.02/M CPU-ms. [C1] | A small deployment might fit free usage, but test SSR/admin CPU before promising that. $5 is an account baseline, not necessarily incremental if already paid. |
| D1 | Free: 5M rows read/day, 100K rows written/day, 5 GB total; paid includes 25B reads/month, 50M writes/month and 5 GB, then $0.001/M reads, $1/M writes and $0.75/GB-month. [C2] | Rows scanned, not pageviews, determine usage; free-limit exhaustion makes queries fail. |
| R2 Standard | 10 GB-month, 1M Class A and 10M Class B operations/month free; then $0.015/GB-month, $4.50/M A and $0.36/M B; no egress charge. [C3] | A small media library may fit, but uploads, retrievals and backups are separate metered work. |
| Optional services | Images free tier covers 5,000 unique transformations/month; additional KV/email/plugins depend on configuration. [E2][C1] | Omit unneeded services; the minimal comparison is not an all-features CMS. |

Cloudflare lists ordinary static-asset requests as free/unlimited, but the current site runs its Worker first; do not infer that every current request bypasses Worker metering. Workers Caching also has its own request billing behavior. Static Astro removes D1/R2 dependence for public content regardless of whether we optimize that dispatch later. [C1][L1]

No defensible engineering-hours quote follows from reading docs alone. The added work has at least five concrete ownership areas: runtime integration, editorial schema/templates, admin/credential setup, migration/deploy management, and database/media recovery. The plain-Astro build and release-script migration is common to both options; CMS operations are additional. [E2–E6]

## Revisit trigger and limits of this research

Reopen the CMS decision when a named editor needs to publish without a code deploy, scheduled/multi-author posts become real requirements, or frequent media/content changes make repository editing a measurable bottleneck. A future pilot should use separate preview D1/R2 resources and pass: edit→preview→publish, scheduled publish, media upload/read, scoped MCP write, feed-byte preservation, stable download redirect, CPU/latency observation, and full database/media recovery. EmDash can be added to an existing Astro project, so deferring it does not block that path. [E2][E3][E4][E6]

Not confirmed: installed EmDash package behavior, production permissions/billing, actual latency or CPU, current traffic, restore duration, or compatibility of this repository with a built EmDash artifact. No dependencies, CMS infrastructure, production website configuration or release script were changed for this research. Source documentation is live and can change; repository evidence below is pinned to the inspected commit.

## Sources

- [M1] [Map #21: site destination and constraints](https://github.com/saiashirwad/sendpoint/issues/21).
- [E1] [EmDash 1.0 announcement, 2026-09-28](https://emdashcms.com/blog/emdash-1-0).
- [E2] [EmDash: Deploy to Cloudflare](https://docs.emdashcms.com/deployment/cloudflare/).
- [E3] [EmDash: Add to an existing Astro project](https://docs.emdashcms.com/existing-project/).
- [E4] [EmDash: MCP server reference](https://docs.emdashcms.com/reference/mcp-server/).
- [E5] [EmDash: Core database migrations](https://docs.emdashcms.com/deployment/core-migrations/).
- [E6] [EmDash: Backups and recovery](https://docs.emdashcms.com/guides/backups/).
- [A1] [Astro: Content collections](https://docs.astro.build/en/guides/content-collections/).
- [A2] [Astro: Project structure, public assets](https://docs.astro.build/en/basics/project-structure/#public).
- [C1] [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/).
- [C2] [Cloudflare D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/).
- [C3] [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/).
- [L1] [`web/wrangler.jsonc`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/web/wrangler.jsonc#L1-L15).
- [L2] [`web/src/worker.js`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/web/src/worker.js#L1-L16).
- [L3] [`release.sh`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/release.sh): appcast path at L81; website path at L127; stable release asset at L130–153; resume deploy at L156–177; feed generation, conditional rewrite, staging and deploy at L222–263.
- [L4] [`web/public/appcast.xml`](https://github.com/saiashirwad/sendpoint/blob/3288cbacb3872f65845636e843319adc203b074c/web/public/appcast.xml#L1-L43).
