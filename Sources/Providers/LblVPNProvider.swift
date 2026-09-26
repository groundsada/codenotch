import Foundation
import os

/// The LBL tunnel: whether the Cisco Secure Client's `LBL-MFA-VPN` profile is
/// connected. Same contract as the ESnet ring — read from `vpnctl status`,
/// nothing held here.
///
/// This tunnel is a full tunnel by design and the two VPNs are mutually
/// exclusive (verified 2026-09-23, both orderings). The ring says which side
/// is connected; the switching itself stays in `vpnctl` / the menu-bar widget.
actor LblVPNProvider: UsageProvider {
    nonisolated let id = "lbl-vpn"
    nonisolated let displayName = "LBL VPN"
    nonisolated let glyph = ProviderGlyph.lbl

    nonisolated private let config: EsnotchConfig
    nonisolated private let output: @Sendable (EsnotchConfig) throws -> String

    init(
        config: EsnotchConfig = .load(),
        output: @escaping @Sendable (EsnotchConfig) throws -> String = { config in
            try EsnotchShell.captureScript(path: config.vpnctlPath, arguments: ["status"])
        }
    ) {
        self.config = config
        self.output = output
    }

    nonisolated var isVisibleWhenAbsent: Bool { true }

    nonisolated var signInRoute: SignInRoute {
        .openApp(bundleID: config.ciscoBundleID, name: "Cisco Secure Client")
    }

    nonisolated func account() -> ProviderAccount? { nil }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let text = try await EsnotchShell.run { try self.output(self.config) }
        guard let up = VpnState.reading(text, key: "LBL") else {
            throw UsageProviderError.badResponse(status: 0)
        }
        Log.usage.debug("lbl-vpn: up=\(up, privacy: .public)")
        return VpnState.snapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            up: up,
            detail: L10n.t("full tunnel · MFA")
        )
    }

    /// The Cisco GUI opens for the login/MFA step; the CLI threads the actual
    /// connect, exactly as `vpnctl lbl` does.
    nonisolated func presentSignIn() {
        Task.detached {
            try? EsnotchShell.capture(executable: URL(fileURLWithPath: "/usr/bin/open"),
                                      arguments: ["-a", "Cisco Secure Client"])
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            try? EsnotchShell.captureScript(path: self.config.vpnctlPath, arguments: ["lbl"])
        }
    }

    nonisolated func signOut() async {
        await Task.detached {
            try? EsnotchShell.capture(executable: URL(fileURLWithPath: "/opt/cisco/secureclient/bin/vpn"),
                                      arguments: ["disconnect"])
        }.value
    }

    nonisolated func forgetCachedCredential() {}
}
