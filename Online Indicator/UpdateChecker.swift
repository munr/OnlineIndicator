import Foundation
import AppKit

class UpdateChecker {

    static let repoOwner = "bornexplorer"
    static let repoName  = "OnlineIndicator"

    private static var apiURL: URL? {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")
    }

    enum UpdateResult {
        case upToDate
        case updateAvailable(releaseTag: String, notes: String?, downloadURL: URL?, pageURL: URL)
        case error(String)
    }

    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents  = local.split(separator: ".").compactMap { Int($0) }
        let maxLength = max(remoteComponents.count, localComponents.count)

        for i in 0..<maxLength {
            let remoteValue = i < remoteComponents.count ? remoteComponents[i] : 0
            let localValue  = i < localComponents.count  ? localComponents[i]  : 0

            if remoteValue > localValue { return true  }
            if remoteValue < localValue { return false }
        }

        return false
    }

    static func check(completion: @escaping (UpdateResult) -> Void) {
        guard let url = apiURL else {
            completion(.error("Invalid repository URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.error(error.localizedDescription))
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    completion(.error("Invalid response from GitHub"))
                    return
                }

                // GitHub returns an error object when repo/release not found
                if let message = json["message"] as? String {
                    completion(.error(message))
                    return
                }

                guard let tag = json["tag_name"] as? String,
                      let pageURLString = json["html_url"] as? String,
                      let pageURL = URL(string: pageURLString)
                else {
                    completion(.error("Unexpected response format"))
                    return
                }

                // Strip a leading "v" from the tag (e.g. "v1.2.0" → "1.2.0") before comparing
                let remoteVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let localVersion  = AppInfo.marketingVersion

                guard isNewer(remoteVersion, than: localVersion) else {
                    completion(.upToDate)
                    return
                }

                let notes = json["body"] as? String

                // Prefer the first .dmg asset; fall back to the release page
                var downloadURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    let dmg = assets.first {
                        ($0["name"] as? String)?.hasSuffix(".dmg") == true
                    }
                    if let dmgURLString = dmg?["browser_download_url"] as? String {
                        downloadURL = URL(string: dmgURLString)
                    }
                }

                completion(.updateAvailable(
                    releaseTag:  tag,
                    notes:       notes,
                    downloadURL: downloadURL,
                    pageURL:     pageURL
                ))
            }
        }.resume()
    }
}
