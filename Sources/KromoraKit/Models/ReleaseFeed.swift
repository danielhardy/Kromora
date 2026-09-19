#if KROMORA_DIRECT_DISTRIBUTION
import Foundation

/// The release data needed by the updater, independent of GitHub's complete payload.
public struct KromoraRelease: Sendable, Equatable {
    public let version: AppVersion
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let diskImageURL: URL?
    public let diskImageSize: Int?

    public init(
        version: AppVersion,
        title: String,
        notes: String,
        pageURL: URL,
        diskImageURL: URL?,
        diskImageSize: Int? = nil
    ) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.diskImageURL = diskImageURL
        self.diskImageSize = diskImageSize
    }
}

/// Unauthenticated GitHub Releases feed access for the Kromora repository.
public enum KromoraReleaseFeed {
    public static let repository = "danielhardy/Kromora"

    public enum FeedError: LocalizedError, Equatable {
        case badStatus(Int)
        case unusableTag(String)
        case insecureURL

        public var errorDescription: String? {
            switch self {
            case .badStatus(let status): return "GitHub answered with status \(status)."
            case .unusableTag(let tag): return "The latest release is tagged \"\(tag)\", which is not a version."
            case .insecureURL: return "GitHub returned an insecure release URL."
            }
        }
    }

    public static func latestURL(repository: String = repository) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    public static func fetchLatest(
        repository: String = repository,
        session: URLSession = .shared
    ) async throws -> KromoraRelease {
        var request = URLRequest(url: latestURL(repository: repository))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Kromora/\(AppVersion.current?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.badStatus(http.statusCode)
        }
        return try parse(data)
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            let size: Int?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    /// Decodes a fixture without network access. A missing DMG is valid and is surfaced in the UI.
    public static func parse(_ data: Data) throws -> KromoraRelease {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let version = AppVersion(payload.tagName) else {
            throw FeedError.unusableTag(payload.tagName)
        }
        guard payload.htmlURL.scheme?.lowercased() == "https" else {
            throw FeedError.insecureURL
        }
        let asset = payload.assets?.first {
            $0.name.lowercased().hasSuffix(".dmg")
                && $0.browserDownloadURL.scheme?.lowercased() == "https"
        }
        return KromoraRelease(
            version: version,
            title: payload.name?.isEmpty == false ? payload.name! : "Kromora \(version)",
            notes: payload.body ?? "",
            pageURL: payload.htmlURL,
            diskImageURL: asset?.browserDownloadURL,
            diskImageSize: asset?.size
        )
    }
}

public typealias Release = KromoraRelease
public typealias ReleaseFeed = KromoraReleaseFeed
#endif
