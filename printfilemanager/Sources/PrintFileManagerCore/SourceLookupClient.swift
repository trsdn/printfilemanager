import Foundation

public enum SourceVersionStatus: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case current
    case possibleUpdateAvailable
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .current: "Current"
        case .possibleUpdateAvailable: "Possible update available"
        case .unknown: "Unknown"
        }
    }
}

public struct SourceLookupCandidate: Equatable, Sendable {
    public var title: String
    public var url: URL
    public var snippet: String

    public init(title: String, url: URL, snippet: String = "") {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public struct SourceLookupResult: Equatable, Sendable {
    public var sourceInfo: PrintSourceInfo?
    public var title: String?
    public var description: String?
    public var latestVersion: String?
    public var versionStatus: SourceVersionStatus
    public var updatedAt: Date?
    public var checkedAt: Date
    public var searchQuery: String?
    public var matchConfidence: Double?

    public init(
        sourceInfo: PrintSourceInfo? = nil,
        title: String? = nil,
        description: String? = nil,
        latestVersion: String? = nil,
        versionStatus: SourceVersionStatus = .unknown,
        updatedAt: Date? = nil,
        checkedAt: Date = Date(),
        searchQuery: String? = nil,
        matchConfidence: Double? = nil
    ) {
        self.sourceInfo = sourceInfo
        self.title = title
        self.description = description
        self.latestVersion = latestVersion
        self.versionStatus = versionStatus
        self.updatedAt = updatedAt
        self.checkedAt = checkedAt
        self.searchQuery = searchQuery
        self.matchConfidence = matchConfidence
    }
}

public enum SourceLookupError: Error, Equatable, LocalizedError {
    case noSourceFound
    case invalidSearchResponse
    case invalidPageResponse

    public var errorDescription: String? {
        switch self {
        case .noSourceFound:
            "No matching source page was found."
        case .invalidSearchResponse:
            "The source search response could not be read."
        case .invalidPageResponse:
            "The source page response could not be read."
        }
    }
}

struct SourcePageMetadata: Equatable, Sendable {
    var url: URL
    var title: String?
    var description: String?
    var author: String?
    var version: String?
    var modifiedAt: Date?
    var canonicalURL: URL?
}

public struct SourceLookupClient {
    /// Web search and page fetches are best-effort enrichment, so they must fail fast rather than
    /// block the inspector on an unresponsive host.
    static let requestTimeout: TimeInterval = 20
    public init() {}

    public func lookup(record: PrintFileRecord, settings: AIEnrichmentSettings? = nil) async throws -> SourceLookupResult {
        let checkedAt = Date()
        let lookupTarget = try await lookupTarget(for: record, settings: settings)
        let page = try await fetchPageMetadata(from: lookupTarget.candidate.url)
        let sourceURL = page.canonicalURL ?? page.url
        let sourceInfo = PrintSourceInfo(
            platform: Self.platformName(from: sourceURL) ?? record.sourceInfo?.platform,
            author: page.author,
            license: nil,
            url: sourceURL.absoluteString,
            downloadedAt: record.sourceInfo?.downloadedAt
        )

        return SourceLookupResult(
            sourceInfo: sourceInfo.hasAnyLookupValue ? sourceInfo : nil,
            title: page.title ?? lookupTarget.candidate.title,
            description: page.description,
            latestVersion: page.version,
            versionStatus: Self.versionStatus(for: record, page: page),
            updatedAt: page.modifiedAt,
            checkedAt: checkedAt,
            searchQuery: lookupTarget.query,
            matchConfidence: lookupTarget.confidence
        )
    }

    private func lookupTarget(for record: PrintFileRecord, settings: AIEnrichmentSettings?) async throws -> LookupTarget {
        if let existingURL = Self.normalizedURL(from: record.sourceInfo?.url) {
            return LookupTarget(candidate: SourceLookupCandidate(title: record.projectName ?? record.fileName, url: existingURL), query: nil, confidence: 1)
        }

        let queries = Self.searchQueries(for: record)
        var candidates: [SourceLookupCandidate] = []
        var queryUsed: String?
        for query in queries.prefix(4) {
            let results = try await searchWeb(query: query)
            if !results.isEmpty, queryUsed == nil {
                queryUsed = query
            }
            candidates.append(contentsOf: results)
            candidates = Self.uniqueCandidates(candidates)
            if candidates.count >= 8 { break }
        }

        guard !candidates.isEmpty else { throw SourceLookupError.noSourceFound }

        if let settings,
           let choice = try? await AIEnrichmentClient().sourceLookupChoice(for: record, candidates: Array(candidates.prefix(8)), settings: settings) {
            return LookupTarget(candidate: choice.candidate, query: queryUsed, confidence: choice.confidence)
        }

        guard let candidate = Self.bestDeterministicCandidate(for: record, candidates: candidates) else {
            throw SourceLookupError.noSourceFound
        }
        return LookupTarget(candidate: candidate, query: queryUsed, confidence: nil)
    }

    private func searchWeb(query: String) async throws -> [SourceLookupCandidate] {
        var components = URLComponents(string: "https://duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw SourceLookupError.invalidSearchResponse }

        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.setValue("Mozilla/5.0 PrintFileManager/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw SourceLookupError.invalidSearchResponse
        }

        return Self.parseSearchResults(from: String(decoding: data, as: UTF8.self))
    }

    private func fetchPageMetadata(from url: URL) async throws -> SourcePageMetadata {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.setValue("Mozilla/5.0 PrintFileManager/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<400).contains(httpResponse.statusCode) else {
            throw SourceLookupError.invalidPageResponse
        }

        return Self.parsePageMetadata(from: String(decoding: data, as: UTF8.self), url: url)
    }

    static func searchQueries(for record: PrintFileRecord) -> [String] {
        let name = searchName(for: record)
        let exactName = "\"\(name)\""
        let platforms = likelySearchSites(for: record)
        return platforms.flatMap { site in
            ["\(exactName) site:\(site)", "\(name) site:\(site)"]
        }
    }

    static func parseSearchResults(from html: String) -> [SourceLookupCandidate] {
        let anchors = matches(pattern: #"(?is)<a\b[^>]*class=["'][^"']*result__a[^"']*["'][^>]*>.*?</a>"#, in: html)
        let candidates = anchors.compactMap { anchor -> SourceLookupCandidate? in
            let attributes = Self.attributes(in: anchor)
            guard let href = attributes["href"], let url = resolvedSearchResultURL(from: href) else { return nil }
            guard isLikelyModelSourceURL(url) else { return nil }
            let title = cleanHTML(anchor.replacingOccurrences(of: #"(?is)<a\b[^>]*>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?is)</a>"#, with: "", options: .regularExpression))
            return SourceLookupCandidate(title: title, url: url)
        }
        return uniqueCandidates(candidates)
    }

    static func parsePageMetadata(from html: String, url: URL) -> SourcePageMetadata {
        let title = firstMetaContent(in: html, names: ["og:title", "twitter:title"])
            ?? firstTitle(in: html)
        let description = firstMetaContent(in: html, names: ["og:description", "twitter:description", "description"])
        let author = firstMetaContent(in: html, names: ["author", "article:author"])
        let version = firstVersion(in: html)
        let modifiedAt = firstDate(in: html, names: ["article:modified_time", "dateModified", "modified_time", "updatedAt"])
        let canonicalURL = firstCanonicalURL(in: html, baseURL: url)

        return SourcePageMetadata(
            url: url,
            title: title,
            description: description,
            author: author,
            version: version,
            modifiedAt: modifiedAt,
            canonicalURL: canonicalURL
        )
    }

    static func versionStatus(for record: PrintFileRecord, page: SourcePageMetadata) -> SourceVersionStatus {
        if let remoteVersion = page.version,
           let localVersion = firstMetadataValue(record.metadata, keys: ["version", "Version", "modelVersion", "profileVersion", "source.version"]) {
            return normalizedVersion(remoteVersion) == normalizedVersion(localVersion) ? .current : .possibleUpdateAvailable
        }

        if let modifiedAt = page.modifiedAt,
           let localDate = record.sourceInfo?.downloadedAt ?? record.modifiedAt {
            return modifiedAt > localDate.addingTimeInterval(24 * 60 * 60) ? .possibleUpdateAvailable : .current
        }

        return .unknown
    }

    static func bestDeterministicCandidate(for record: PrintFileRecord, candidates: [SourceLookupCandidate]) -> SourceLookupCandidate? {
        let recordTokens = significantTokens(in: searchName(for: record))
        let scored = candidates.map { candidate in
            let haystack = "\(candidate.title) \(candidate.url.absoluteString) \(candidate.snippet)".lowercased()
            let tokenMatches = recordTokens.filter { haystack.contains($0) }.count
            let platformBoost = likelySearchSites(for: record).contains { candidate.url.host(percentEncoded: false)?.contains($0) == true } ? 2 : 0
            return (candidate, tokenMatches + platformBoost)
        }
        .sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= max(2, min(4, recordTokens.count / 2)) else { return nil }
        return best.0
    }

    private static func searchName(for record: PrintFileRecord) -> String {
        let rawName = record.projectName ?? record.url.deletingPathExtension().lastPathComponent
        return rawName
            .replacingOccurrences(of: ".3mf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func likelySearchSites(for record: PrintFileRecord) -> [String] {
        let hints = ([record.sourceInfo?.platform].compactMap { $0 } + record.sourceHints + [record.relativePath, record.fileName])
            .joined(separator: " ")
            .lowercased()
        var sites: [String] = []
        if hints.contains("makerworld") || hints.contains("bambu") { sites.append("makerworld.com") }
        if hints.contains("printables") { sites.append("printables.com") }
        if hints.contains("thingiverse") { sites.append("thingiverse.com") }
        sites.append(contentsOf: ["makerworld.com", "printables.com", "thingiverse.com", "cults3d.com"])
        var seen = Set<String>()
        return sites.filter { seen.insert($0).inserted }
    }

    private static func uniqueCandidates(_ candidates: [SourceLookupCandidate]) -> [SourceLookupCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.url.absoluteString).inserted
        }
    }

    private static func normalizedURL(from value: String?) -> URL? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        return URL(string: value)
    }

    private static func resolvedSearchResultURL(from href: String) -> URL? {
        let decoded = htmlDecoded(href)
        if decoded.hasPrefix("//") {
            return resolvedSearchResultURL(from: "https:\(decoded)")
        }
        guard let url = URL(string: decoded) else { return nil }
        if url.host(percentEncoded: false)?.contains("duckduckgo.com") == true,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let resolved = URL(string: uddg.removingPercentEncoding ?? uddg) {
            return resolved
        }
        return url
    }

    private static func isLikelyModelSourceURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        let path = url.path.lowercased()
        if host.contains("makerworld.com") { return path.contains("/models/") || path.contains("/model/") }
        if host.contains("printables.com") { return path.contains("/model/") }
        if host.contains("thingiverse.com") { return path.contains("/thing:") || path.contains("/thing/") }
        if host.contains("cults3d.com") { return path.contains("/3d-model/") || path.contains("/models/") }
        return false
    }

    private static func platformName(from url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.contains("makerworld") { return "MakerWorld" }
        if host.contains("printables") { return "Printables" }
        if host.contains("thingiverse") { return "Thingiverse" }
        if host.contains("cults3d") { return "Cults" }
        if host.contains("github") { return "GitHub" }
        return nil
    }

    private static func firstMetaContent(in html: String, names: [String]) -> String? {
        let wanted = Set(names.map { $0.lowercased() })
        for tag in matches(pattern: #"(?is)<meta\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            let key = attributes["property"] ?? attributes["name"] ?? attributes["itemprop"]
            guard let key, wanted.contains(key.lowercased()), let content = attributes["content"] else { continue }
            let cleaned = cleanHTML(content)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private static func firstCanonicalURL(in html: String, baseURL: URL) -> URL? {
        for tag in matches(pattern: #"(?is)<link\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            guard attributes["rel"]?.lowercased().contains("canonical") == true, let href = attributes["href"] else { continue }
            return URL(string: htmlDecoded(href), relativeTo: baseURL)?.absoluteURL
        }
        return nil
    }

    private static func firstTitle(in html: String) -> String? {
        guard let title = matches(pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#, in: html, captureGroup: 1).first else { return nil }
        let cleaned = cleanHTML(title)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func firstVersion(in html: String) -> String? {
        let patterns = [
            #"(?is)["'](?:modelVersion|versionName|version|latestVersion)["']\s*:\s*["']([^"']{1,80})["']"#,
            #"(?is)\bVersion\s*</[^>]+>\s*<[^>]+>\s*([^<]{1,80})<"#
        ]
        for pattern in patterns {
            if let match = matches(pattern: pattern, in: html, captureGroup: 1).first {
                let cleaned = cleanHTML(match)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    private static func firstDate(in html: String, names: [String]) -> Date? {
        if let metaValue = firstMetaContent(in: html, names: names), let date = parseDate(metaValue) {
            return date
        }
        let keyPattern = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"(?is)["'](?:"# + keyPattern + #")["']\s*:\s*["']([^"']{8,80})["']"#
        for match in matches(pattern: pattern, in: html, captureGroup: 1) {
            if let date = parseDate(cleanHTML(match)) { return date }
        }
        return nil
    }

    private static func firstMetadataValue(_ metadata: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func normalizedVersion(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func significantTokens(in value: String) -> [String] {
        let ignored = Set(["3mf", "bambu", "makerworld", "printables", "model", "models", "for", "and", "the", "with"])
        return value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !ignored.contains($0) }
    }

    private static func attributes(in tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for match in matches(pattern: #"([A-Za-z_:.-]+)\s*=\s*(["'])(.*?)\2"#, in: tag, captureGroups: [1, 3]) {
            guard match.count == 2 else { continue }
            attributes[match[0].lowercased()] = htmlDecoded(match[1])
        }
        return attributes
    }

    private static func cleanHTML(_ value: String) -> String {
        htmlDecoded(value)
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlDecoded(_ value: String) -> String {
        var decoded = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        while let range = decoded.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let entity = String(decoded[range])
            let digits = entity.dropFirst(2).dropLast()
            guard let scalar = UInt32(digits), let unicodeScalar = UnicodeScalar(scalar) else { break }
            decoded.replaceSubrange(range, with: String(Character(unicodeScalar)))
        }
        return decoded
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        return nil
    }

    private static func matches(pattern: String, in value: String, captureGroup: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > captureGroup, let range = Range(match.range(at: captureGroup), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func matches(pattern: String, in value: String, captureGroups: [Int]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).map { match in
            captureGroups.compactMap { group in
                guard match.numberOfRanges > group, let range = Range(match.range(at: group), in: value) else { return nil }
                return String(value[range])
            }
        }
    }

    private struct LookupTarget {
        var candidate: SourceLookupCandidate
        var query: String?
        var confidence: Double?
    }
}

private extension PrintSourceInfo {
    var hasAnyLookupValue: Bool {
        platform != nil || author != nil || license != nil || url != nil
    }
}
