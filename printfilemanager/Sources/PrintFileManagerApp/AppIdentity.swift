import Foundation

/// Identity the build stamped into the bundle.
///
/// Read from `Info.plist` rather than hardcoded, so the version shown in the app and the links it
/// offers cannot drift from the artifact they were built into.
enum AppIdentity {
    static let name = string(for: "CFBundleName") ?? "Print File Manager"
    static let version = string(for: "CFBundleShortVersionString") ?? "unknown"
    static let build = string(for: "CFBundleVersion") ?? "unknown"
    static let copyright = string(for: "NSHumanReadableCopyright") ?? ""
    static let licenseIdentifier = string(for: "PFMLicenseIdentifier") ?? ""
    static let repositoryURL = url(for: "PFMRepositoryURL")
    static let issueTrackerURL = url(for: "PFMIssueTrackerURL")

    static var versionDescription: String {
        "Version \(version) (\(build))"
    }

    private static func string(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func url(for key: String) -> URL? {
        string(for: key).flatMap(URL.init(string:))
    }
}
