import Foundation

/// Describes an endpoint's transport without blocking it.
///
/// An earlier version of this refused plain `http` unless the host was loopback. That was wrong
/// twice over. It blocked the setup this app exists for -- a self-hosted model server on the
/// user's own network, which cannot have a certificate because no authority issues one for
/// `192.168.2.177` -- and it made a security judgement on the user's behalf about their own
/// machine and their own network.
///
/// The endpoint is the user's to choose. This type only says what is worth knowing about it, so
/// the interface can show a note next to a genuinely risky combination. Nothing here refuses a
/// request.
public enum EndpointTransportPolicy {
    public enum Advice: Equatable {
        /// Nothing worth saying: https, or plain http that cannot leave the local network.
        case none
        /// Plain http to a host that is reachable from the internet. Worth a note, not a block --
        /// and only actually sensitive when there is a credential to expose.
        case plaintextToPublicHost(host: String, carriesAPIKey: Bool)
    }

    public static func advice(for url: URL, hasAPIKey: Bool) -> Advice {
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !isPrivate(host: host)
        else { return .none }

        return .plaintextToPublicHost(host: host, carriesAPIKey: hasAPIKey)
    }

    /// A short sentence for the interface, or nil when there is nothing to say.
    public static func note(for url: URL, hasAPIKey: Bool) -> String? {
        switch advice(for: url, hasAPIKey: hasAPIKey) {
        case .none:
            return nil
        case .plaintextToPublicHost(let host, let carriesAPIKey):
            return carriesAPIKey
                ? "Sent over plain http to \(host), so the API key is readable in transit."
                : "Sent over plain http to \(host), so requests are readable in transit."
        }
    }

    /// Whether a host is unroutable outside the local network. Used only to decide whether a note
    /// is worth showing.
    public static func isPrivate(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        // mDNS names resolve only on the local link.
        if host == "local" || host.hasSuffix(".local") { return true }

        if let v4 = IPv4(host) { return v4.isPrivate }
        return isPrivateIPv6(host)
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        if host == "::1" { return true }
        // fe80::/10 link-local and fc00::/7 unique local.
        let head = host.prefix(4).lowercased()
        if head.hasPrefix("fe8") || head.hasPrefix("fe9") || head.hasPrefix("fea") || head.hasPrefix("feb") {
            return true
        }
        if head.hasPrefix("fc") || head.hasPrefix("fd") { return true }
        return false
    }

    /// A dotted-quad address, parsed strictly: anything that is not four decimal octets is treated
    /// as a hostname.
    struct IPv4 {
        let octets: [Int]

        init?(_ text: String) {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            var parsed: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                      let value = Int(part), (0...255).contains(value)
                else { return nil }
                parsed.append(value)
            }
            octets = parsed
        }

        var isPrivate: Bool {
            switch (octets[0], octets[1]) {
            case (127, _): return true                    // loopback
            case (10, _): return true                     // RFC 1918
            case (172, 16...31): return true              // RFC 1918
            case (192, 168): return true                  // RFC 1918
            case (169, 254): return true                  // link-local
            default: return false
            }
        }
    }
}
