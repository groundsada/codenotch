import Foundation
import os

/// The ESnet gateway's monthly spend, from its public Prometheus `/metrics/`
/// counter.
///
/// The arithmetic belongs to `~/.hermes/scripts/esnet_gateway.py` — month
/// rollover baselines, gateway-restart carry-forward, offline freezes — the
/// same script the user's existing menu-bar widget already runs. Duplicating
/// that logic inside the app would be a second copy of the bug, so this
/// provider refreshes the script and reads its state file. No credentials
/// touch this app: `/metrics/` is public for the account email.
actor EsnetSpendProvider: UsageProvider {
    nonisolated let id = "esnet-spend"
    nonisolated let displayName = "ESnet spend"
    nonisolated let glyph = ProviderGlyph.esnetSpend

    nonisolated private let config: EsnotchConfig
    /// Refreshes the gateway state. Production runs `esnet_gateway.py`, which
    /// writes `esnet_gateway.json`; a test supplies its own state, so nothing
    /// has to be spawned or resolved.
    nonisolated private let refresh: @Sendable (EsnotchConfig) -> Void
    /// Reads the state file the refresh wrote.
    nonisolated private let stateData: @Sendable (EsnotchConfig) throws -> Data

    init(
        config: EsnotchConfig = .load(),
        refresh: @escaping @Sendable (EsnotchConfig) -> Void = { config in
            _ = try? EsnotchShell.captureScript(path: config.esnetGatewayScript)
        },
        stateData: @escaping @Sendable (EsnotchConfig) throws -> Data = { config in
            try EsnotchShell.readJSON(path: config.esnetGatewayState)
        }
    ) {
        self.config = config
        self.refresh = refresh
        self.stateData = stateData
    }

    nonisolated var isVisibleWhenAbsent: Bool { true }

    nonisolated var signInRoute: SignInRoute {
        .guidance(L10n.t("Spend comes from the gateway's public /metrics/ — no key needed. It needs the ESnet VPN up."))
    }

    nonisolated func account() -> ProviderAccount? { nil }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        refresh(config)
        let data = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try self.stateData(self.config) })
            }
        }
        let state = try JSONDecoder().decode(State.self, from: data)
        return Self.snapshot(state: state)
    }

    nonisolated static func snapshot(state: State, now: Date = Date()) -> ProviderSnapshot {
        let budget = state.budget
        let fraction: Double? = budget > 0 ? min(max(state.spend / budget, 0), 1) : nil
        var windows: [LimitWindow] = [
            LimitWindow(
                id: "month",
                label: L10n.t("This month"),
                usedFraction: fraction,
                money: UsageMoneyBreakdown(
                    currency: "USD",
                    spent: state.spend,
                    remaining: max(budget - state.spend, 0)
                ),
                resetsAt: monthStart(after: state.month),
                duration: 31 * 86400
            )
        ]
        for model in state.byModel {
            windows.append(LimitWindow(
                id: "model:\(model.model)",
                label: model.model,
                usedText: Self.dollars(model.spend),
                detail: L10n.t("this month"),
                prefersUsedText: true
            ))
        }

        let staleSince = state.updatedDate.flatMap { date in
            now.timeIntervalSince(date) > Self.staleAfter ? date : nil
        }
        return ProviderSnapshot(
            id: "esnet-spend",
            displayName: "ESnet spend",
            glyph: .esnetSpend,
            fidelity: .derived,
            status: staleSince.map(ProviderStatus.stale) ?? .ok,
            windows: windows,
            headlineID: "month"
        )
    }

    static let staleAfter: TimeInterval = 6 * 3600

    /// The gateway state file: everything the script computes, the fields the
    /// ring needs. Unknown fields are ignored so the script can grow.
    struct State: Decodable {
        let month: String
        let spend: Double
        let budget: Double
        let updated: String?
        let by_model: [ModelSpend]?

        struct ModelSpend: Decodable {
            let model: String
            let spend: Double
        }

        var byModel: [ModelSpend] { by_model ?? [] }
        var updatedDate: Date? {
            guard let updated else { return nil }
            return ISO8601DateFormatter().date(from: updated)
        }
    }

    /// `"2026-09"` → the first of the following month (UTC — the counters
    /// reset where the gateway lives, not where the Mac does).
    nonisolated static func monthStart(after month: String) -> Date? {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, let year = parts.first, let m = parts.last,
              (1...12).contains(m) else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        components.year = year
        components.month = m + 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        if m == 12 {
            components.year = year + 1
            components.month = 1
        }
        return components.date
    }

    nonisolated static func dollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
