import XCTest
@testable import Codenotch

/// The ESnet/LBL edition's providers, with everything injected or parsed from
/// fixture text — no subprocess ever runs, so the essence (what the output
/// means) is tested without a VPN or a login.
final class EsnotchProvidersTests: XCTestCase {
    // MARK: VPN state

    func testVpnStateParsing() {
        let esnetUp = "ESnet: CONNECTED\nLBL:   not connected\n"
        XCTAssertEqual(VpnState.reading(esnetUp, key: "ESnet"), true)
        XCTAssertEqual(VpnState.reading(esnetUp, key: "LBL"), false)

        let lblUp = "ESnet: not connected\nLBL:   CONNECTED\n"
        XCTAssertEqual(VpnState.reading(lblUp, key: "ESnet"), false)
        XCTAssertEqual(VpnState.reading(lblUp, key: "LBL"), true)

        XCTAssertNil(VpnState.reading("nothing here", key: "ESnet"))
    }

    func testVpnUpSnapshot() {
        let up = VpnState.snapshot(
            id: "esnet-vpn", displayName: "ESnet VPN",
            glyph: .esnet, up: true, detail: "split tunnel")
        XCTAssertEqual(up.headlineText, "UP")
        XCTAssertEqual(up.headline?.usedFraction, 1.0)
        XCTAssertEqual(up.headline?.bandOverride, .ample)
        XCTAssertEqual(up.status, .ok)
        XCTAssertTrue(up.hasReading)
    }

    func testVpnDownSnapshot() {
        let down = VpnState.snapshot(
            id: "lbl-vpn", displayName: "LBL VPN",
            glyph: .lbl, up: false, detail: "full tunnel")
        XCTAssertEqual(down.headlineText, "DOWN")
        XCTAssertEqual(down.headline?.usedFraction, 0.0)
        XCTAssertEqual(down.headline?.bandOverride, .critical)
        XCTAssertEqual(down.status, .ok)
    }

    // MARK: ESnet gateway state

    func testEsnetSpendSnapshot() throws {
        let json = Data("""
        {"month":"2026-09","spend":118.124,"budget":500.0,\
        "updated":"2026-09-25T15:36:06Z",\
        "by_model":[{"model":"claude-opus-5","spend":32.18}]}
        """.utf8)
        let state = try JSONDecoder().decode(EsnetSpendProvider.State.self, from: json)
        let snap = EsnetSpendProvider.snapshot(state: state, now: Date())
        XCTAssertEqual(snap.id, "esnet-spend")
        XCTAssertEqual(snap.headline?.id, "month")
        XCTAssertEqual(snap.headline?.usedFraction ?? 0, 118.124 / 500, accuracy: 0.0001)
        XCTAssertEqual(snap.headline?.money?.spent, 118.124)
        XCTAssertEqual(snap.windows.count, 2)
        XCTAssertEqual(snap.windows[1].label, "claude-opus-5")
        XCTAssertEqual(snap.windows[1].usedText, "$32.18")
        XCTAssertEqual(snap.status, .ok)
    }

    func testEsnetSpendStaleReading() throws {
        let json = Data("""
        {"month":"2026-09","spend":118.124,"budget":500.0,"updated":"2026-01-01T00:00:00Z"}
        """.utf8)
        let state = try JSONDecoder().decode(EsnetSpendProvider.State.self, from: json)
        let snap = EsnetSpendProvider.snapshot(state: state, now: Date())
        guard case .stale = snap.status else {
            return XCTFail("expected a stale reading for a months-old update")
        }
    }

    func testMonthStartAcrossYearRollover() throws {
        let date = try XCTUnwrap(EsnetSpendProvider.monthStart(after: "2026-12"))
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(parts.year, 2027)
        XCTAssertEqual(parts.month, 1)
        XCTAssertEqual(parts.day, 1)
    }

    // MARK: CBorg

    func testCborgSnapshot() throws {
        let json = Data("""
        {"user_info":{"spend":42.5,"max_budget":250.0,\
        "budget_reset_at":"2026-10-01T00:00:00Z"},\
        "keys":[{"name":"claude","spend":42.5}]}
        """.utf8)
        let response = try JSONDecoder().decode(CborgSpendProvider.Response.self, from: json)
        let user = try XCTUnwrap(response.userInfo)
        let snap = CborgSpendProvider.snapshot(user: user, keys: response.keys ?? [])
        XCTAssertEqual(snap.headline?.usedFraction ?? 0, 42.5 / 250, accuracy: 0.0001)
        XCTAssertEqual(snap.windows.count, 2)
        XCTAssertEqual(snap.windows[1].label, "claude")
        XCTAssertEqual(snap.status, .ok)
    }

    func testCborgIPLockedError() throws {
        let json = Data("""
        {"error":{"message":"Access denied: IP address not recognized",\
        "type":"ip_not_authorized","code":403}}
        """.utf8)
        let response = try JSONDecoder().decode(CborgSpendProvider.Response.self, from: json)
        XCTAssertNil(response.userInfo)
        XCTAssertEqual(response.error?.ipNotAuthorized, true)
    }

    // MARK: Glyphs

    func testEsnotchGlyphOutlines() {
        for glyph in [ProviderGlyph.esnet, .lbl, .esnetSpend, .cborg] {
            XCTAssertFalse(glyph.outline.isEmpty, "\(glyph.rawValue) needs a fallback outline")
            XCTAssertFalse(glyph.assetName.isEmpty)
        }
        XCTAssertEqual(ProviderGlyph.esnet.rawValue, "esnet")
        XCTAssertEqual(ProviderGlyph.cborg.rawValue, "cborg")
    }
}
