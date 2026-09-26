import Foundation

/// Where the ESnet/LBL toolchain lives on this machine.
///
/// The notch reads the same scripts and state files the user's existing
/// menu-bar widget already runs (`~/.hermes/scripts/vpnctl`, the ESnet gateway
/// fetcher, the CBorg fetcher), so the two UIs can never disagree. Every path
/// can be overridden in `~/Library/Application Support/Codenotch/esnotch.json`
/// (or `$ESNOTCH_CONFIG_PATH`, which tests use to point at a fixture tree).
struct EsnotchConfig: Sendable, Equatable, Decodable {
    var home: String
    var vpnctlPath: String
    var esnetGatewayScript: String
    var esnetGatewayState: String
    var cborgScript: String
    var cborgCache: String
    var viscosityBundleID: String
    var ciscoBundleID: String
    var ciscoProfile: String
    var esnetConnectionName: String

    /// The known layout of this Mac. A fresh clone plus `~/.hermes/scripts`
    /// is enough — no config file required.
    static func `default`(home: String = NSHomeDirectory()) -> EsnotchConfig {
        let h = (home as NSString).expandingTildeInPath
        return EsnotchConfig(
            home: h,
            vpnctlPath: "\(h)/.hermes/scripts/vpnctl",
            esnetGatewayScript: "\(h)/.hermes/scripts/esnet_gateway.py",
            esnetGatewayState: "\(h)/.hermes/state/esnet_gateway.json",
            cborgScript: "\(h)/.hermes/scripts/cborg_spend.sh",
            cborgCache: "\(h)/.hermes/state/cborg_spend.json",
            viscosityBundleID: "com.viscosityvpn.Viscosity",
            ciscoBundleID: "com.cisco.secureclient.gui",
            ciscoProfile: "LBL-MFA-VPN",
            esnetConnectionName: "ESnet VPN West (split tunnel) - IPv6 workaround"
        )
    }

    static func load(
        applicationSupport: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EsnotchConfig {
        var config: EsnotchConfig
        if let home = environment["HOME"], !home.isEmpty {
            config = .default(home: home)
        } else {
            config = .default()
        }
        let base = applicationSupport
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let file: URL
        if let override = environment["ESNOTCH_CONFIG_PATH"], !override.isEmpty {
            file = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        } else {
            file = base.appendingPathComponent("Codenotch", isDirectory: true)
                .appendingPathComponent("esnotch.json")
        }
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(EsnotchConfig.self, from: data)
        else { return config }

        config.merge(decoded)
        return config
    }

    /// Non-empty values from the file win; empty strings are treated as
    /// "leave the default".
    private mutating func merge(_ other: EsnotchConfig) {
        func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }
        if !other.vpnctlPath.isEmpty { vpnctlPath = expand(other.vpnctlPath) }
        if !other.esnetGatewayScript.isEmpty { esnetGatewayScript = expand(other.esnetGatewayScript) }
        if !other.esnetGatewayState.isEmpty { esnetGatewayState = expand(other.esnetGatewayState) }
        if !other.cborgScript.isEmpty { cborgScript = expand(other.cborgScript) }
        if !other.cborgCache.isEmpty { cborgCache = expand(other.cborgCache) }
        if !other.viscosityBundleID.isEmpty { viscosityBundleID = other.viscosityBundleID }
        if !other.ciscoBundleID.isEmpty { ciscoBundleID = other.ciscoBundleID }
        if !other.ciscoProfile.isEmpty { ciscoProfile = other.ciscoProfile }
        if !other.esnetConnectionName.isEmpty { esnetConnectionName = other.esnetConnectionName }
    }
}

extension EsnotchConfig {
    /// Every key is optional: a file with one override still reads. Kept in
    /// an extension so the memberwise initializer survives.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        home = try container.decodeIfPresent(String.self, forKey: .home) ?? ""
        vpnctlPath = try container.decodeIfPresent(String.self, forKey: .vpnctlPath) ?? ""
        esnetGatewayScript = try container.decodeIfPresent(String.self, forKey: .esnetGatewayScript) ?? ""
        esnetGatewayState = try container.decodeIfPresent(String.self, forKey: .esnetGatewayState) ?? ""
        cborgScript = try container.decodeIfPresent(String.self, forKey: .cborgScript) ?? ""
        cborgCache = try container.decodeIfPresent(String.self, forKey: .cborgCache) ?? ""
        viscosityBundleID = try container.decodeIfPresent(String.self, forKey: .viscosityBundleID) ?? ""
        ciscoBundleID = try container.decodeIfPresent(String.self, forKey: .ciscoBundleID) ?? ""
        ciscoProfile = try container.decodeIfPresent(String.self, forKey: .ciscoProfile) ?? ""
        esnetConnectionName = try container.decodeIfPresent(String.self, forKey: .esnetConnectionName) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case home
        case vpnctlPath
        case esnetGatewayScript
        case esnetGatewayState
        case cborgScript
        case cborgCache
        case viscosityBundleID
        case ciscoBundleID
        case ciscoProfile
        case esnetConnectionName
    }
}
