import Foundation

/// Checks GitHub Releases for a newer version. No auto-download; it just
/// compares the latest tag with the running version and exposes the URL.
struct UpdateChecker {
    /// GitHub "owner/repo".
    static let repo = "fdtorres1/AgentMeter"
    static var releasesURL: URL {
        URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    struct Result {
        let latestVersion: String
        let isNewer: Bool
        let url: URL
    }

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    static func check() async throws -> Result {
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: api)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.unavailable
        }
        struct Release: Decodable {
            let tagName: String
            let htmlUrl: String
            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlUrl = "html_url"
            }
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return Result(
            latestVersion: latest,
            isNewer: isVersion(latest, newerThan: currentVersion),
            url: URL(string: release.htmlUrl) ?? releasesURL
        )
    }

    /// Semantic-ish comparison of dot-separated numeric versions.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Could not check for updates" }
}
