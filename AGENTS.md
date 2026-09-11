# Engineering rules

- Use Swift Observation for app-owned state. Do not add `ObservableObject`, `@Published`, or TCA.
- Model finite workflows with closed enums, one event transition function, and one idempotent teardown path.
- Keep data transformations pure and outside views.
- Give each lifecycle task one owner. Retain and cancel its handle; do not use `Task.detached` for lifecycle work.
- Check cancellation around external calls. Apply a result only when its full context still matches the current state.
- Inject small system boundaries for deterministic tests. Test behavior, including cancellation, stale results, invalid transitions, and teardown.
- Make clean cutovers. Delete obsolete callers, state, settings, imports, and files.
- Publish only with `./release.sh X.Y.Z --ad-hoc --publish`.
