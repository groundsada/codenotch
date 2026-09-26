import Foundation

/// The reading `vpnctl status` produces, and the snapshot a tunnel ring draws.
///
/// The two tunnels are mutually exclusive by design (verified 2026-09-23), so
/// the two rings are genuinely independent facts — each says whether *its*
/// tunnel is the one carrying traffic right now.
enum VpnState {
    /// `"ESnet:   CONNECTED"` → true, `"ESnet: not connected"` → false.
    /// Nil when the output never mentions the tunnel at all — a different
    /// shape than "down", and worth surfacing rather than painting over.
    static func reading(_ text: String, key: String) -> Bool? {
        for line in text.split(whereSeparator: \.isNewline) {
            let components = line.split(maxSplits: 1, whereSeparator: { $0 == ":" })
            guard components.count == 2 else { continue }
            let name = components[0].trimmingCharacters(in: .whitespaces)
            let value = components[1].trimmingCharacters(in: .whitespaces)
            if name == key { return value == "CONNECTED" }
        }
        return nil
    }

    /// Connected: a full arc in the accent colour with "UP" under it.
    /// Disconnected: no arc, "DOWN", and a red ring — the one state that
    /// actually costs the user something. The window is deliberately not a
    /// percentage of anything: a tunnel has no quota, and inventing a
    /// denominator would be a lie in a shape.
    static func snapshot(
        id: String,
        displayName: String,
        glyph: ProviderGlyph,
        up: Bool,
        detail: String
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: [
                LimitWindow(
                    id: "tunnel",
                    label: L10n.t("Tunnel"),
                    usedFraction: up ? 1.0 : 0.0,
                    bandOverride: up ? .ample : .critical,
                    usedText: up ? "UP" : "DOWN",
                    detail: detail,
                    prefersUsedText: true
                )
            ],
            headlineID: "tunnel"
        )
    }
}
