import Foundation
import os

/// The CBorg account's per-key spend and budget, from `api.cborg.lbl.gov`.
///
/// The API is IP-locked to LBLnet — from home or the ESnet tunnel it answers
/// 403. The credential belongs to `~/.config/claude-cborg.env` and is never
/// read by this app; the provider runs the same `cborg_spend.sh` the user's
/// widget already uses, which fetches, scrubs the echoed tokens and caches.
/// On cache the network call is skipped unless the cache is old, so a 60-second
/// poll is free when the reading has barely moved.
actor CborgSpendProvider: UsageProvider {
    nonisolated let id = "cborg-spend"
    nonisolated let displayName = "CBorg spend"
    nonisolated let glyph = ProviderGlyph.cborg

    nonisolated private let config: EsnotchConfig
    /// Fetch-and-cache. Production runs `cborg_spend.sh`; a test supplies its
    /// own cached JSON.
    nonisolated private let fetch: @Sendable (EsnotchConfig) -> Void
    nonisolated private let cacheData: @Sendable (EsnotchConfig) throws -> Data
    nonisolated private let cacheAge: @Sendable (EsnotchConfig) -> TimeInterval?

    init(
        config: EsnotchConfig = .load(),
        fetch: @escaping @Sendable (EsnotchConfig) -> Void = { config in
            _ = try? EsnotchShell.captureScript(path: config.cborgScript)
        },
        cacheData: @escaping @Sendable (EsnotchConfig) throws -> Data = { config in
            try EsnotchShell.readJSON(path: config.cborgCache)
        },
        cacheAge: @escaping @Sendable (EsnotchConfig) -> TimeInterval? = { config in
            let expanded = (config.cborgCache as NSString).expandingTildeInPath
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: expanded),
                  let modified = attrs[.modificationDate] as? Date else { return nil }
            return Date().timeIntervalSince(modified)
        }
    ) {
        self.config = config
        self.fetch = fetch
        self.cacheData = cacheData
        self.cacheAge = cacheAge
    }

    nonisolated var isVisibleWhenAbsent: Bool { true }

    nonisolated var signInRoute: SignInRoute {
        .guidance(L10n.t("CBorg's API is reachable from LBLnet only — connect via the LBL VPN to refresh the spend."))
    }

    nonisolated func account() -> ProviderAccount? { nil }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        // Only the fetch when the cache is stale; a fresh reading is the
        // reading, and the API has bigger problems than a gently ageing cache.
        if let age = cacheAge(config), age > Self.maxCacheAge {
            fetch(config)
        }
        let data = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try self.cacheData(self.config) })
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let failure = response.error {
            throw UsageProviderError.apiError(
                failure.ipNotAuthorized
                    ? L10n.t("CBorg API is IP-locked to LBLnet (403) — connect via the LBL VPN to refresh")
                    : L10n.t("CBorg API: \(failure.message)")
            )
        }
        guard let user = response.userInfo else {
            throw UsageProviderError.badResponse(status: 0)
        }
        return Self.snapshot(user: user, keys: response.keys ?? [])
    }

    /// How stale is stale: refresh every five minutes at most, like the
    /// menu-bar widget did.
    static let maxCacheAge: TimeInterval = 5 * 60

    nonisolated static func snapshot(
        user: Response.UserInfo,
        keys: [Response.Key],
        now: Date = Date()
    ) -> ProviderSnapshot {
        let budget = user.maxBudget ?? 0
        let fraction: Double? = budget > 0 ? min(max(user.spend / budget, 0), 1) : nil
        var windows: [LimitWindow] = [
            LimitWindow(
                id: "month",
                label: L10n.t("This month"),
                usedFraction: fraction,
                money: UsageMoneyBreakdown(
                    currency: "USD",
                    spent: user.spend,
                    remaining: max(budget - user.spend, 0)
                ),
                resetsAt: user.budgetResetAt,
                duration: 31 * 86400
            )
        ]
        for key in keys {
            windows.append(LimitWindow(
                id: "key:\(key.name)",
                label: key.name,
                usedText: EsnetSpendProvider.dollars(key.spend ?? 0),
                detail: L10n.t("key"),
                prefersUsedText: true
            ))
        }
        return ProviderSnapshot(
            id: "cborg-spend",
            displayName: "CBorg spend",
            glyph: .cborg,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: "month"
        )
    }

    /// The script's cached response, with every field optional: the API is
    /// versioned independently of this app and the error shape shows up on
    /// ordinary days (off-net).
    struct Response: Decodable {
        let user_info: UserInfo?
        let keys: [Key]?
        let error: Failure?

        struct UserInfo: Decodable {
            let spend: Double
            let max_budget: Double?
            let budget_reset_at: String?
            var maxBudget: Double? { max_budget }
            var budgetResetAt: Date? {
                guard let budget_reset_at else { return nil }
                return ISO8601DateFormatter().date(from: budget_reset_at)
            }
        }

        struct Key: Decodable {
            let name: String
            let spend: Double?
        }

        struct Failure: Decodable {
            let message: String
            let type: String?
            let code: Int?
            var ipNotAuthorized: Bool {
                type == "ip_not_authorized" || code == 403
            }
        }

        var userInfo: UserInfo? { user_info }
    }
}
