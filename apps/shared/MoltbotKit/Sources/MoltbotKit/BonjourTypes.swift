import Foundation

public enum MoltbotBonjour {
    // v0: 仅内部使用，可能会重命名。
    public static let gatewayServiceType = "_moltbot-gw._tcp"
    public static let gatewayServiceDomain = "local."
    public static let wideAreaGatewayServiceDomain = "moltbot.internal."

    public static let gatewayServiceDomains = [
        gatewayServiceDomain,
        wideAreaGatewayServiceDomain,
    ]

    public static func normalizeServiceDomain(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return self.gatewayServiceDomain
        }

        let lower = trimmed.lowercased()
        if lower == "local" || lower == "local." {
            return self.gatewayServiceDomain
        }

        return lower.hasSuffix(".") ? lower : (lower + ".")
    }
}
