import AppKit
import SendpointDomain
import Foundation

struct CapturedApplication: Hashable, Sendable {
    let identity: ApplicationIdentity
    let processIdentifier: pid_t
}

/// The one injected boundary used to resolve provenance for a captured app.
struct ProvenanceProbe: Sendable {
    typealias Lookup = @Sendable (CapturedApplication) async throws -> ProvenanceFields
    typealias ApplicationValidator = @Sendable (CapturedApplication) async throws -> Bool

    private let validateApplication: ApplicationValidator
    private let genericLookup: Lookup
    private let providers: [String: ProvenanceProvider]

    init(
        validateApplication: @escaping ApplicationValidator = { _ in true },
        genericLookup: @escaping Lookup,
        providers: [ProvenanceProvider] = []
    ) {
        self.validateApplication = validateApplication
        self.genericLookup = genericLookup
        var registry: [String: ProvenanceProvider] = [:]
        for provider in providers {
            for bundleID in provider.bundleIDs {
                precondition(registry[bundleID] == nil, "Duplicate provenance provider for \(bundleID)")
                registry[bundleID] = provider
            }
        }
        self.providers = registry
    }

    func probe(_ application: CapturedApplication) async -> Provenance {
        let empty = Provenance(application: application.identity)
        let baselineFields: ProvenanceFields
        do {
            try Task.checkCancellation()
            guard try await validateApplication(application) else { return empty }
            try Task.checkCancellation()
            baselineFields = try await genericLookup(application)
            try Task.checkCancellation()
            guard try await validateApplication(application) else { return empty }
            try Task.checkCancellation()
        } catch {
            return empty
        }

        let baseline = provenance(application.identity, baselineFields)
        guard let bundleID = application.identity.bundleID,
              let provider = providers[bundleID]
        else { return baseline }

        do {
            try Task.checkCancellation()
            guard try await validateApplication(application) else { return baseline }
            try Task.checkCancellation()
            let fields = try await provider.lookup(application)
            try Task.checkCancellation()
            guard try await validateApplication(application) else { return baseline }
            try Task.checkCancellation()
            return provenance(application.identity, baselineFields.merging(fields))
        } catch {
            return baseline
        }
    }

    static func live() -> Self {
        Self(
            validateApplication: { try await ProvenanceSystemBoundary.matchesCapturedApplication($0) },
            genericLookup: {
                try await ProvenanceSystemBoundary.focusedWindowFields(
                    processIdentifier: $0.processIdentifier
                )
            },
            providers: ProvenanceProvider.live
        )
    }

    private func provenance(
        _ identity: ApplicationIdentity,
        _ fields: ProvenanceFields
    ) -> Provenance {
        Provenance(
            application: identity,
            windowTitle: fields.windowTitle,
            url: fields.url,
            workingDirectory: fields.workingDirectory
        )
    }
}

