import Foundation
import os

/// The ESnet tunnel: whether Viscosity's "ESnet VPN West (split tunnel) - IPv6
/// workaround" connection is actually carrying traffic right now.
///
/// State comes from the same `vpnctl status` the user's existing menu-bar
/// widget uses — one truth, two renderings. No credential lives here: the
/// YubiKey PIV challenge happens inside Viscosity, not in this app.
actor EsnetVPNProvider: UsageProvider {
    nonisolated let id = "esnet-vpn"
    nonisolated let displayName = "ESnet VPN"
    nonisolated let glyph = ProviderGlyph.esnet

    nonisolated private let config: EsnotchConfig
    /// Injected status text. Production runs `vpnctl status`; a test supplies
    /// a fixed string so nothing has to be spawned.
    nonisolated private let output: @Sendable (EsnotchConfig) throws -> String
    /// How a connect is requested. Injected for the same reason, and because
    /// `vpnctl esnet` sleeps while it works — not a thing a test should do.
    nonisolated private let connect: @Sendable (EsnotchConfig) -> Void

    init(
        config: EsnotchConfig = .load(),
        output: @escaping @Sendable (EsnotchConfig) throws -> String = { config in
            try EsnotchShell.captureScript(path: config.vpnctlPath, arguments: ["status"])
        },
        connect: @escaping @Sendable (EsnotchConfig) -> Void = { config in
            _ = try? EsnotchShell.captureScript(path: config.vpnctlPath, arguments: ["esnet"])
        }
    ) {
        self.config = config
        self.output = output
        self.connect = connect
    }

    /// The tunnel is worth a ring whether or not it is up — that is the point
    /// of the ring.
    nonisolated var isVisibleWhenAbsent: Bool { true }

    nonisolated var signInRoute: SignInRoute {
        .openApp(bundleID: config.viscosityBundleID, name: "Viscosity")
    }

    /// Nothing an account: the YubiKey login belongs to Viscosity.
    nonisolated func account() -> ProviderAccount? { nil }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let text = try await EsnotchShell.run { try self.output(self.config) }
        guard let up = VpnState.reading(text, key: "ESnet") else {
            throw UsageProviderError.badResponse(status: 0)
        }
        Log.usage.debug("esnet-vpn: up=\(up, privacy: .public)")
        return VpnState.snapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            up: up,
            detail: L10n.t("split tunnel · YubiKey")
        )
    }

    /// Connect from the ring: no terminal window, no credentials — the same
    /// request `vpnctl esnet` makes.
    nonisolated func presentSignIn() {
        Task.detached { self.connect(self.config) }
    }

    nonisolated func signOut() async {
        // The tunnel only, never the other one: dropping both would be a
        // surprise on a machine that is also using LBL.
        await Task.detached { try? EsnotchShell.capture(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: [
            "-e", "tell application \"Viscosity\" to disconnect \"\(self.config.esnetConnectionName)\""
        ]) }.value
    }

    nonisolated func forgetCachedCredential() {}
}
