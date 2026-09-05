import Foundation

/// An application family and its enrichment strategy. The probe owns execution,
/// validation, cancellation and fallback; providers do not start independent tasks.
struct ProvenanceProvider: Sendable {
    let bundleIDs: Set<String>
    let lookup: ProvenanceProbe.Lookup

    init(bundleIDs: Set<String>, lookup: @escaping ProvenanceProbe.Lookup) {
        precondition(!bundleIDs.isEmpty && bundleIDs.allSatisfy { !$0.isEmpty })
        self.bundleIDs = bundleIDs
        self.lookup = lookup
    }

    static let live: [Self] = [
        .ghostty,
        .terminal,
        .kitty,
        .chromiumBrowsers,
        .safariBrowsers,
        .codeEditors,
    ]
}
