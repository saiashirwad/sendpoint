# Engineering Guidelines

## State and architecture

- Use Swift Observation (`@Observable`) for app-owned state. Do not mix it with `ObservableObject` or `@Published`.
- Use closed state enums for finite lifecycles and modes.
- Model events as explicit transition methods. Avoid scattered boolean guards and implicit state changes.
- Give each lifecycle one idempotent teardown path.
- Keep prompt composition and other data transformations pure and outside views.
- Do not add The Composable Architecture piecemeal. Use the native Observation model consistently.

## Concurrency

- Give each asynchronous task one clear owner.
- Never use `Task.detached` for work owned by a capture, panel, window, or feature lifecycle.
- Retain lifecycle task handles, cancel them during teardown, and clear them.
- Treat cancellation as cooperative: check it before and after external calls.
- Before applying a late result, verify its capture token, annotation ID, and original session ID.
- Keep UI state and UI mutations on `@MainActor`.

## Boundaries and tests

- Inject filesystem, pasteboard, provenance, permission, and other system boundaries where deterministic tests need substitutes.
- Test observable state transitions and behavior, not source layout or implementation details.
- Cover cancellation, stale-result rejection, invalid transitions, and teardown paths.
- Prefer a small explicit dependency boundary over a framework or protocol hierarchy.
- Make clean cutovers: remove obsolete callers, state fields, settings keys, imports, and files.

## Releasing

- Cut and publish a release with one command: `./release.sh X.Y.Z --ad-hoc --publish`. Drop `--ad-hoc` once a Developer ID certificate and notary profile exist.
- That command bumps the version, builds, tags, pushes, publishes the GitHub release, points the website's download button at the new zip, and deploys the site with wrangler. Do not do those steps by hand or split them across commits.
- The website's download link must always match the latest GitHub release. If you touch `web/public/index.html`, keep the link pointing at `releases/download/vX.Y.Z/Sendpoint-X.Y.Z.zip` for the current version in `Resources/Info.plist`.
- Pushing to `main` does not deploy the site. Only `wrangler deploy` from `web/` does.
