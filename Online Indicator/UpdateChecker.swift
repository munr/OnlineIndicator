import Foundation
import AppKit

final class UpdateChecker {

    static let repoOwner = "munr"
    static let repoName  = "mac-online-indicator"

    private static var apiURL: URL? {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")
    }

    enum UpdateResult {
        case upToDate
        case updateAvailable(releaseTag: String, notes: String?, downloadURL: URL?, pageURL: URL)
        case error(String)
    }

    // MARK: - GitHub API response model

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlUrl: URL
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }

    // MARK: - Version comparison

    private static func versionComponents(from version: String) -> [Int] {
        // Extract every numeric run so we handle tags like:
        // "v1.2.3", "1.2.3-beta.1", and "1.2.3 (Build abc123)".
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsVersion = version as NSString
        let fullRange = NSRange(location: 0, length: nsVersion.length)
        return regex.matches(in: version, options: [], range: fullRange).compactMap {
            Int(nsVersion.substring(with: $0.range))
        }
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteComponents = versionComponents(from: remote)
        let localComponents  = versionComponents(from: local)
        let maxLength = max(remoteComponents.count, localComponents.count)

        for i in 0..<maxLength {
            let remoteValue = i < remoteComponents.count ? remoteComponents[i] : 0
            let localValue  = i < localComponents.count  ? localComponents[i]  : 0

            if remoteValue > localValue { return true  }
            if remoteValue < localValue { return false }
        }

        return false
    }

    // MARK: - Cached result (persisted across launches)

    /// The cached update result stored from the last successful check.
    static var cachedResult: UpdateResult? {
        guard let tag = UserDefaults.standard.string(for: .lastUpdateTag),
              let pageString = UserDefaults.standard.string(for: .lastUpdatePage),
              let pageURL = URL(string: pageString) else { return nil }

        // If the cached release is not newer than the currently installed app version,
        // clear stale state and hide the update CTA.
        guard isNewer(tag, than: AppInfo.marketingVersion) else {
            persistResult(.upToDate)
            return nil
        }

        let notes = UserDefaults.standard.string(for: .lastUpdateNotes)
        let downloadURL = UserDefaults.standard.string(for: .lastUpdateDownload).flatMap(URL.init)
        return .updateAvailable(releaseTag: tag, notes: notes, downloadURL: downloadURL, pageURL: pageURL)
    }

    private static func persistResult(_ result: UpdateResult) {
        switch result {
        case .updateAvailable(let tag, let notes, let downloadURL, let pageURL):
            UserDefaults.standard.set(tag,                          for: .lastUpdateTag)
            UserDefaults.standard.set(notes,                        for: .lastUpdateNotes)
            UserDefaults.standard.set(downloadURL?.absoluteString,  for: .lastUpdateDownload)
            UserDefaults.standard.set(pageURL.absoluteString,       for: .lastUpdatePage)
        case .upToDate:
            UserDefaults.standard.removeObject(for: .lastUpdateTag)
            UserDefaults.standard.removeObject(for: .lastUpdateNotes)
            UserDefaults.standard.removeObject(for: .lastUpdateDownload)
            UserDefaults.standard.removeObject(for: .lastUpdatePage)
        case .error:
            break
        }
    }

    // MARK: - Automatic check

    /// Checks for updates at most once every 24 hours. Calls `completion` only when a result
    /// is actually fetched; skips silently if the cooldown has not elapsed.
    static func checkIfNeeded(completion: @escaping (UpdateResult) -> Void) {
        let lastCheck = UserDefaults.standard.object(for: .lastUpdateCheck) as? Date
        let oneDayAgo = Date().addingTimeInterval(-86_400)
        guard lastCheck == nil || lastCheck! < oneDayAgo else { return }

        check { result in
            UserDefaults.standard.set(Date(), for: .lastUpdateCheck)
            completion(result)
        }
    }

    // MARK: - Manual check

    static func check(completion: @escaping (UpdateResult) -> Void) {
        guard let url = apiURL else {
            completion(.error("Invalid repository URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.error(error.localizedDescription))
                    return
                }

                guard let data else {
                    completion(.error("Invalid response from GitHub"))
                    return
                }

                // GitHub returns a JSON object with a "message" key for errors (e.g. rate limit, not found).
                if let errorPayload = try? JSONDecoder().decode([String: String].self, from: data),
                   let message = errorPayload["message"] {
                    completion(.error(message))
                    return
                }

                guard let release = try? decoder.decode(GitHubRelease.self, from: data) else {
                    completion(.error("Unexpected response format"))
                    return
                }

                // Strip a leading "v" from the tag (e.g. "v1.2.0" → "1.2.0") before comparing.
                let remoteVersion = release.tagName.hasPrefix("v")
                    ? String(release.tagName.dropFirst())
                    : release.tagName

                guard isNewer(remoteVersion, than: AppInfo.marketingVersion) else {
                    persistResult(.upToDate)
                    completion(.upToDate)
                    return
                }

                // Prefer the first .dmg asset; fall back to the release page.
                let downloadURL = release.assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadUrl

                let result = UpdateResult.updateAvailable(
                    releaseTag:  release.tagName,
                    notes:       release.body,
                    downloadURL: downloadURL,
                    pageURL:     release.htmlUrl
                )
                persistResult(result)
                completion(result)
            }
        }.resume()
    }
}
