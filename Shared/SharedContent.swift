import Foundation
import UniformTypeIdentifiers

#if canImport(MobileCoreServices)
import MobileCoreServices
#endif

/// Everything the share sheet handed us about the thing the user tapped "Share" on.
///
/// The point of the experiment is partly to *see* what actually arrives, so this
/// keeps the raw type identifiers around alongside the resolved values.
struct SharedContent: Sendable {
    var url: URL?
    var text: String?

    /// One row per (attachment, registered UTI) pair, for the inspector panel.
    var rawItems: [RawItem]

    struct RawItem: Identifiable, Sendable {
        let id = UUID()
        let typeIdentifier: String
        let resolvedPreview: String?
    }

    var isEmpty: Bool {
        url == nil && (text?.isEmpty ?? true)
    }

    /// The block we feed to the model as grounding context.
    var contextBlock: String {
        var parts: [String] = []
        if let url {
            parts.append("URL: \(url.absoluteString)")
        }
        if let text, !text.isEmpty {
            parts.append("Shared text:\n\(text)")
        }
        return parts.joined(separator: "\n\n")
    }

    static let empty = SharedContent(url: nil, text: nil, rawItems: [])
}

#if canImport(UIKit)
import UIKit

enum SharedContentLoader {

    static func load(from context: NSExtensionContext?) async -> SharedContent {
        guard let items = context?.inputItems as? [NSExtensionItem] else {
            return .empty
        }

        var url: URL?
        var text: String?
        var raw: [SharedContent.RawItem] = []

        for item in items {
            if let attributed = item.attributedContentText?.string,
               !attributed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = attributed
            }

            for provider in item.attachments ?? [] {
                for uti in provider.registeredTypeIdentifiers {
                    let value = await provider.loadValue(for: uti)

                    switch value {
                    case .url(let resolvedURL):
                        if !resolvedURL.isFileURL, url == nil {
                            url = resolvedURL
                        }
                    case .string(let resolvedString):
                        if uti == UTType.plainText.identifier || uti == UTType.text.identifier,
                           text == nil || text?.isEmpty == true {
                            text = resolvedString
                        }
                        // A plain-text attachment sometimes *is* a bare URL string.
                        if url == nil,
                           let u = URL(string: resolvedString.trimmingCharacters(in: .whitespacesAndNewlines)),
                           u.scheme?.hasPrefix("http") == true {
                            url = u
                        }
                    case .data, .other, .none:
                        break
                    }

                    raw.append(.init(typeIdentifier: uti, resolvedPreview: value.preview))
                }
            }
        }

        return SharedContent(url: url, text: text, rawItems: raw)
    }
}

/// A `Sendable` snapshot of whatever an `NSItemProvider` resolved to — the cast
/// happens inside the completion handler so no non-`Sendable` value crosses the
/// concurrency boundary.
private enum LoadedValue: Sendable {
    case url(URL)
    case string(String)
    case data(Int)
    case other(String)
    case none

    var preview: String? {
        switch self {
        case .url(let u): return u.absoluteString
        case .string(let s): return String(s.prefix(500))
        case .data(let count): return "\(count) bytes"
        case .other(let name): return name
        case .none: return nil
        }
    }
}

private extension NSItemProvider {
    /// Completion-handler API wrapped so the loader can stay linear and `async`.
    func loadValue(for typeIdentifier: String) async -> LoadedValue {
        await withCheckedContinuation { continuation in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, _ in
                let resolved: LoadedValue
                switch value {
                case let u as URL: resolved = .url(u)
                case let s as String: resolved = .string(s)
                case let a as NSAttributedString: resolved = .string(a.string)
                case let d as Data: resolved = .data(d.count)
                case let other?: resolved = .other(String(describing: Swift.type(of: other)))
                case nil: resolved = .none
                }
                continuation.resume(returning: resolved)
            }
        }
    }
}
#endif
