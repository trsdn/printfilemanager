import Foundation

/// Describes an endpoint's transport without blocking it.
///
/// An earlier version of this refused plain `http` unless the host was loopback. That was wrong
/// twice over. It blocked the setup this app exists for -- a self-hosted model server on the
/// user's own network, which cannot have a certificate because no authority issues one for
/// `192.168.2.177` -- and it made a security judgement on the user's behalf about their own
/// machine and their own network.
///
/// The endpoint is the user's to choose. This type only says what is worth knowing about it.
/// Nothing here refuses a request -- but App Transport Security does, and what it refuses was
/// measured rather than assumed:
///
/// | endpoint | result from a sandboxed build with no `NSAppTransportSecurity` key |
/// |---|---|
/// | `http://192.168.2.177:8080` | allowed, HTTP 200 on the first attempt |
/// | `http://modelserver:8080` (dotless) | allowed; failed at DNS, not at ATS |
/// | `http://printer.local:8080` | allowed; reached the network |
/// | `http://models.lan:8080` | **refused, `NSURLErrorDomain -1022`** |
/// | `http://neverssl.com` | **refused, `NSURLErrorDomain -1022`** |
///
/// So the hosts this type recognises are exactly the ones ATS exempts automatically, and a note
/// here means the request will not merely be readable -- it will not be made at all.
public enum EndpointTransportPolicy {
    /// The schemes an endpoint may use. Plain http stays allowed -- a model server on the user's
    /// own network cannot hold a certificate -- but a scheme that cannot carry a request at all
    /// is refused rather than handed to `URLSession` to fail obscurely.
    public static func isSupportedScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public enum Advice: Equatable {
        /// Nothing worth saying: https, or plain http to a host the system treats as local.
        case none
        /// Plain http to a host the system does not treat as local, which App Transport Security
        /// refuses outright. Still not blocked here -- the user may fix it by using https, or by
        /// addressing the machine by its address instead of its name.
        case plaintextRefusedByTransportSecurity(host: String, carriesAPIKey: Bool)
    }

    public static func advice(for url: URL, hasAPIKey: Bool) -> Advice {
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !isPrivate(host: host)
        else { return .none }

        return .plaintextRefusedByTransportSecurity(host: host, carriesAPIKey: hasAPIKey)
    }

    /// A short sentence for the interface, or nil when there is nothing to say.
    public static func note(for url: URL, hasAPIKey: Bool) -> String? {
        switch advice(for: url, hasAPIKey: hasAPIKey) {
        case .none:
            return nil
        case .plaintextRefusedByTransportSecurity(let host, let carriesAPIKey):
            // Says what will actually happen. "Readable in transit" described a request that
            // macOS never sends, which left the user looking for a network fault instead of a
            // scheme they can change.
            let refusal = """
                \(host) is not recognised as a local address, so macOS refuses plain http to it. \
                Use https, or address the machine by its IP address.
                """
            return carriesAPIKey
                ? refusal + " Over plain http the API key would also be readable in transit."
                : refusal
        }
    }

    /// Whether the system treats a host as local, using the same rules App Transport Security
    /// applies automatically: loopback, `.local`, an unqualified name, or a private address.
    public static func isPrivate(host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        // mDNS names resolve only on the local link.
        if host == "local" || host.hasSuffix(".local") { return true }

        if let v4 = IPv4(host) { return v4.isPrivate }
        if host.contains(":") { return isPrivateIPv6(host) }

        // An unqualified name cannot be a public host, and ATS lets it through on that basis --
        // `http://modelserver:8080` is a normal way to reach a machine on a home network.
        return !host.contains(".")
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
