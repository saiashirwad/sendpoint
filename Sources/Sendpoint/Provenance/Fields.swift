import Foundation

/// Partial provenance values read from one system boundary.
struct ProvenanceFields: Equatable, Sendable {
    var windowTitle: String?
    var url: URL?
    var workingDirectory: URL?

    init(
        windowTitle: String? = nil,
        url: URL? = nil,
        workingDirectory: URL? = nil
    ) {
        self.windowTitle = windowTitle
        self.url = url
        self.workingDirectory = workingDirectory
    }

    func merging(_ enrichment: Self) -> Self {
        Self(
            windowTitle: enrichment.windowTitle ?? windowTitle,
            url: enrichment.url ?? url,
            workingDirectory: enrichment.workingDirectory ?? workingDirectory
        )
    }
}

