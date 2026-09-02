import Foundation

/// The one network layer. Resolves any shared URL into a `LinkPreview` using
/// only free sources: the page's own HTML (Open Graph / Twitter cards / JSON-LD /
/// readable text) or, for X posts, the community tweet-JSON mirrors.
enum LinkResolver {

    /// Hard cap on what we'll read from a page — the extension has a tight memory budget.
    private static let maxBytes = 1_500_000
    /// Cap on readable text handed to the ~4k-token on-device model.
    private static let maxBodyChars = 3_500

    static func resolve(url: URL, sharedText: String?) async -> LinkPreview {
        if PostEnricher.canEnrich(url), let post = await PostEnricher.fetch(for: url) {
            return post
        }

        guard let (html, finalURL) = await fetchHTML(url) else {
            return .bare(url: url, text: sharedText)
        }

        var preview = parse(html: html, url: url, finalURL: finalURL)
        if (preview.bodyText?.isEmpty ?? true), let sharedText, !sharedText.isEmpty {
            preview.bodyText = sharedText
        }
        return preview
    }

    // MARK: - Fetch

    private static func fetchHTML(_ url: URL) async -> (String, URL)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? "text/html"
            guard type.contains("html") || type.contains("xml") else { return nil }

            var data = Data()
            data.reserveCapacity(min(maxBytes, Int(http.expectedContentLength > 0 ? http.expectedContentLength : 200_000)))
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
            let text = String(decoding: data, as: UTF8.self)
            return (text, http.url ?? url)
        } catch {
            return nil
        }
    }

    // MARK: - Parse

    static func parse(html: String, url: URL, finalURL: URL) -> LinkPreview {
        let meta = HTMLMeta(html: html)
        var preview = LinkPreview(kind: .page, url: url)
        preview.canonicalURL = meta.link(rel: "canonical").flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL } ?? finalURL

        preview.title = meta.first("og:title", "twitter:title") ?? meta.titleTag
        preview.description = meta.first("og:description", "twitter:description", "description")
        preview.siteName = meta.first("og:site_name") ?? finalURL.host.map(Self.prettyHost)
        preview.imageURL = meta.first("og:image", "og:image:url", "twitter:image", "twitter:image:src")
            .flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL }
        preview.faviconURL = meta.favicon(relativeTo: finalURL)
        preview.author = meta.first("author", "article:author", "twitter:creator").map { .init(name: $0) }
        preview.date = meta.first("article:published_time", "og:updated_time", "date").flatMap(Self.parseISO)

        let ogType = meta.first("og:type")?.lowercased() ?? ""
        if let product = meta.jsonLDProduct() {
            preview.kind = .product
            preview.title = product.name ?? preview.title
            preview.priceText = product.priceText
            if let brand = product.brand, preview.siteName == nil { preview.siteName = brand }
        } else if ogType.contains("product") || meta.first("product:price:amount") != nil {
            preview.kind = .product
            if let amount = meta.first("product:price:amount") {
                preview.priceText = formatPrice(amount, currency: meta.first("product:price:currency"))
            }
        } else if ogType.contains("article") || meta.first("article:published_time") != nil {
            preview.kind = .article
        }

        let body = meta.readableText(maxChars: maxBodyChars)
        preview.bodyText = body.isEmpty ? preview.description : body
        return preview
    }

    /// "1245.0" + "USD" → "$1,245"; falls back to the raw text when it isn't a number.
    static func formatPrice(_ raw: String, currency: String?) -> String {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned) else {
            return [raw, currency].compactMap { $0 }.joined(separator: " ")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? raw
    }

    private static func prettyHost(_ host: String) -> String {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare
    }

    private static func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withFullDate]
        return iso.date(from: String(s.prefix(10)))
    }
}

// MARK: - Minimal HTML metadata reader (no WebKit — this runs in an extension)

struct HTMLMeta {
    private let html: String
    private let metas: [[String: String]]
    private let links: [[String: String]]
    let titleTag: String?

    init(html: String) {
        self.html = html
        let head = html.prefix(400_000)
        metas = Self.tags(named: "meta", in: head).map(Self.attributes)
        links = Self.tags(named: "link", in: head).map(Self.attributes)
        titleTag = Self.firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: head).map { Self.clean(Self.decode($0)) }
    }

    /// First non-empty `content` for any of the given `property` / `name` keys.
    func first(_ keys: String...) -> String? {
        for key in keys {
            if let m = metas.first(where: {
                ($0["property"]?.lowercased() == key || $0["name"]?.lowercased() == key || $0["itemprop"]?.lowercased() == key)
                    && !($0["content"]?.isEmpty ?? true)
            }), let content = m["content"] {
                return Self.clean(Self.decode(content))
            }
        }
        return nil
    }

    func link(rel: String) -> String? {
        links.first { ($0["rel"] ?? "").lowercased().split(separator: " ").contains(Substring(rel)) }?["href"]
    }

    func favicon(relativeTo base: URL) -> URL? {
        let candidates = ["apple-touch-icon", "icon", "shortcut icon"]
        for rel in candidates {
            if let href = links.first(where: {
                let rels = ($0["rel"] ?? "").lowercased()
                return rels == rel || rels.split(separator: " ").contains(Substring(rel))
            })?["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL {
                return url
            }
        }
        var comps = URLComponents()
        comps.scheme = base.scheme
        comps.host = base.host
        comps.path = "/favicon.ico"
        return comps.url
    }

    struct Product {
        var name: String?
        var brand: String?
        var priceText: String?
    }

    /// Looks for a JSON-LD `Product` (top level, inside `@graph`, or in an array).
    func jsonLDProduct() -> Product? {
        let blocks = Self.matches(#"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, in: html)
        for raw in blocks {
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let product = Self.findProduct(in: json) { return product }
        }
        return nil
    }

    private static func findProduct(in json: Any) -> Product? {
        if let dict = json as? [String: Any] {
            let type = (dict["@type"] as? String) ?? (dict["@type"] as? [String])?.first ?? ""
            if type.lowercased() == "product" {
                var p = Product()
                p.name = dict["name"] as? String
                if let brand = dict["brand"] as? [String: Any] { p.brand = brand["name"] as? String }
                else if let brand = dict["brand"] as? String { p.brand = brand }
                let offer = (dict["offers"] as? [String: Any]) ?? (dict["offers"] as? [[String: Any]])?.first
                if let offer {
                    let price = (offer["price"] as? String) ?? (offer["price"] as? NSNumber)?.stringValue
                        ?? (offer["lowPrice"] as? String) ?? (offer["lowPrice"] as? NSNumber)?.stringValue
                    let currency = offer["priceCurrency"] as? String
                    if let price { p.priceText = LinkResolver.formatPrice(price, currency: currency) }
                }
                return p
            }
            if let graph = dict["@graph"] as? [Any] {
                for item in graph { if let p = findProduct(in: item) { return p } }
            }
        } else if let array = json as? [Any] {
            for item in array { if let p = findProduct(in: item) { return p } }
        }
        return nil
    }

    /// Visible text with chrome stripped, whitespace collapsed and capped.
    func readableText(maxChars: Int) -> String {
        var s = html
        // Prefer the article/main region when the page marks one.
        if let article = Self.firstMatch(#"<article[\s\S]*?</article>"#, in: s), article.count > 400 {
            s = article
        } else if let main = Self.firstMatch(#"<main[\s\S]*?</main>"#, in: s), main.count > 400 {
            s = main
        }
        for tag in ["script", "style", "noscript", "svg", "nav", "header", "footer", "form", "iframe", "template", "aside"] {
            s = s.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "</?(p|div|br|li|h[1-6]|tr|section|blockquote|dd|dt)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = Self.decode(s)

        var lines: [String] = []
        var total = 0
        for rawLine in s.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{A0}" }).joined(separator: " ")
            // Skip nav crumbs and single words; keep sentences.
            guard line.count >= 40 else { continue }
            lines.append(line)
            total += line.count + 1
            if total >= maxChars { break }
        }
        var out = lines.joined(separator: "\n")
        if out.count > maxChars {
            out = String(out.prefix(maxChars))
            if let lastSpace = out.lastIndex(of: " ") { out = String(out[..<lastSpace]) + "…" }
        }
        return out
    }

    // MARK: Regex helpers

    private static func tags(named name: String, in html: Substring) -> [String] {
        matches("<\(name)\\b([^>]*)>", in: String(html))
    }

    private static func attributes(_ tag: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: #"([a-zA-Z][\w:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#) else { return out }
        let ns = tag as NSString
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            for group in 2...4 where m.range(at: group).location != NSNotFound {
                out[key] = ns.substring(with: m.range(at: group))
                break
            }
        }
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.numberOfRanges > 1 ? $0.range(at: 1) : $0.range)
        }
    }

    private static func firstMatch(_ pattern: String, in text: Substring) -> String? {
        firstMatch(pattern, in: String(text))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first
    }

    private static func clean(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Decodes the entities that actually show up in page metadata.
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&#160;": " ", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–",
            "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“", "&copy;": "©", "&trade;": "™",
        ]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        if let re = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let isHex = m.range(at: 1).length > 0
                let digits = ns.substring(with: m.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}
