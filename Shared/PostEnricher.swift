import Foundation

/// Turns a bare X / Twitter permalink into a `LinkPreview`.
///
/// The X app only shares a permalink, and x.com is behind a login wall, so the
/// only practical free way to get the post body is a community tweet-JSON mirror.
/// Calling this sends the post URL to `fxtwitter.com` (falling back to
/// `vxtwitter.com`). Nothing else leaves the device.
enum PostEnricher {

    /// A tweet id, if `url` looks like a post on X / Twitter (or one of the mirrors).
    static func tweetID(from url: URL?) -> String? {
        guard let url else { return nil }
        let host = url.host?.lowercased() ?? ""
        let known = ["twitter.com", "x.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com", "nitter.net"]
        guard known.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }

        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { $0 == "status" || $0 == "statuses" }),
           i + 1 < parts.count,
           parts[i + 1].allSatisfy(\.isNumber),
           !parts[i + 1].isEmpty {
            return parts[i + 1]
        }
        return nil
    }

    static func canEnrich(_ url: URL?) -> Bool { tweetID(from: url) != nil }

    /// Resolves the post, or `nil` if neither mirror could.
    static func fetch(for url: URL) async -> LinkPreview? {
        guard let id = tweetID(from: url) else { return nil }
        if let fx = await fetchFx(id: id, original: url) { return fx }
        if let vx = await fetchVx(id: id, original: url) { return vx }
        return nil
    }

    /// Plain-text form, kept for the console self-test.
    static func fetchText(for url: URL) async -> String? {
        await fetch(for: url)?.bodyText
    }

    // MARK: - FixTweet

    private static func fetchFx(id: String, original: URL) async -> LinkPreview? {
        guard let endpoint = URL(string: "https://api.fxtwitter.com/status/\(id)") else { return nil }
        guard let data = await get(endpoint),
              let decoded = try? JSONDecoder().decode(FxResponse.self, from: data),
              let tweet = decoded.tweet,
              let text = tweet.text, !text.isEmpty
        else { return nil }

        var preview = LinkPreview(kind: .post, url: original)
        preview.canonicalURL = tweet.url.flatMap(URL.init(string:)) ?? original
        preview.siteName = "X"
        preview.bodyText = text
        preview.faviconURL = URL(string: "https://abs.twimg.com/favicons/twitter.3.ico")
        if let author = tweet.author {
            preview.author = .init(
                name: author.name ?? author.screen_name ?? "Unknown",
                handle: author.screen_name,
                avatarURL: author.avatar_url.flatMap(URL.init(string:)),
                isVerified: author.verified ?? false
            )
        }
        if let created = tweet.created_at {
            preview.date = Self.twitterDate.date(from: created)
        }
        if let photo = tweet.media?.photos?.first?.url ?? tweet.media?.videos?.first?.thumbnail_url {
            preview.imageURL = URL(string: photo)
        }
        if let quote = tweet.quote, let qt = quote.text, !qt.isEmpty {
            preview.quotedText = "@\(quote.author?.screen_name ?? "?"): \(qt)"
        }
        return preview
    }

    private struct FxResponse: Decodable {
        let tweet: Tweet?
        struct Tweet: Decodable {
            let url: String?
            let text: String?
            let created_at: String?
            let author: Author?
            let quote: Quote?
            let media: Media?
        }
        struct Author: Decodable {
            let name: String?
            let screen_name: String?
            let avatar_url: String?
            let verified: Bool?
        }
        struct Quote: Decodable {
            let text: String?
            let author: Author?
        }
        struct Media: Decodable {
            let photos: [Photo]?
            let videos: [Video]?
        }
        struct Photo: Decodable { let url: String? }
        struct Video: Decodable { let thumbnail_url: String? }
    }

    // MARK: - vxTwitter fallback

    private static func fetchVx(id: String, original: URL) async -> LinkPreview? {
        guard let endpoint = URL(string: "https://api.vxtwitter.com/Twitter/status/\(id)") else { return nil }
        guard let data = await get(endpoint),
              let decoded = try? JSONDecoder().decode(VxResponse.self, from: data),
              let text = decoded.text, !text.isEmpty
        else { return nil }

        var preview = LinkPreview(kind: .post, url: original)
        preview.siteName = "X"
        preview.bodyText = text
        if let screen = decoded.user_screen_name {
            preview.author = .init(
                name: decoded.user_name ?? screen,
                handle: screen,
                avatarURL: decoded.user_profile_image_url.flatMap(URL.init(string:))
            )
        }
        if let ts = decoded.date_epoch {
            preview.date = Date(timeIntervalSince1970: ts)
        }
        preview.imageURL = decoded.mediaURLs?.first.flatMap(URL.init(string:))
        return preview
    }

    private struct VxResponse: Decodable {
        let text: String?
        let user_name: String?
        let user_screen_name: String?
        let user_profile_image_url: String?
        let date_epoch: TimeInterval?
        let mediaURLs: [String]?
    }

    // MARK: - Transport

    private static let twitterDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return f
    }()

    private static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("LittleDia/1.0 (iOS share extension)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
