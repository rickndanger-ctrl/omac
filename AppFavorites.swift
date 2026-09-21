import Cocoa

/// Persistent app assignments for Omac's Command-Option favorite shortcuts.
final class AppFavorites {
    static let defaults: [String: String] = [
        "c": "com.anthropic.claudefordesktop",
        "h": "com.nousresearch.hermes.setup",
        "g": "com.openai.codex",
        "b": "com.google.Chrome",
        "e": "com.apple.finder",
        "r": "com.todesktop.230313mzl4w4u92",
        "v": "com.microsoft.VSCode",
        "t": "ru.keepcoder.Telegram",
        "i": "com.apple.MobileSMS",
        "m": "com.apple.mail",
        "s": "com.apple.systempreferences"
    ]

    enum AssignmentError: LocalizedError {
        case invalidKey(String)
        case invalidBundleIdentifier

        var errorDescription: String? {
            switch self {
            case .invalidKey(let key): return "\(key) is not an Omac favorite shortcut."
            case .invalidBundleIdentifier: return "The app bundle identifier is invalid."
            }
        }
    }

    private static let defaultNames: [String: String] = [
        "c": "Claude", "h": "Hermes", "g": "Codex", "b": "Chrome",
        "e": "Finder", "r": "Cursor", "v": "VS Code", "t": "Telegram",
        "i": "Messages", "m": "Mail", "s": "System Settings"
    ]

    private let url: URL
    private var assignments: [String: String]

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            assignments = saved.filter { key, value in
                Self.defaults[key] != nil && Self.isValidBundleIdentifier(value)
            }
        } else {
            assignments = [:]
        }
    }

    func bundle(for key: String) -> String? {
        let normalized = key.lowercased()
        guard Self.defaults[normalized] != nil else { return nil }
        return assignments[normalized] ?? Self.defaults[normalized]
    }

    func assign(key: String, bundleID: String) throws {
        let normalized = key.lowercased()
        guard Self.defaults[normalized] != nil else { throw AssignmentError.invalidKey(key) }
        guard Self.isValidBundleIdentifier(bundleID) else { throw AssignmentError.invalidBundleIdentifier }

        var updated = assignments
        updated[normalized] = bundleID
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        assignments = updated
    }

    func name(for key: String) -> String {
        let normalized = key.lowercased()
        guard let bundleID = bundle(for: normalized) else { return key.uppercased() }
        if bundleID == Self.defaults[normalized], let familiarName = Self.defaultNames[normalized] {
            return familiarName
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let appBundle = Bundle(url: appURL) {
            if let displayName = appBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let bundleName = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !bundleName.isEmpty {
                return bundleName
            }
            return appURL.deletingPathExtension().lastPathComponent
        }
        return "\(bundleID) (unavailable)"
    }

    func renderGuide(_ html: String) -> String {
        let pattern = #"(<span\b[^>]*\bdata-favorite-key\s*=\s*[\"']([chgbErvtimsCHGBERVTIMS])[\"'][^>]*>)(.*?)(</span\s*>)"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return html }

        let rendered = NSMutableString(string: html)
        let matches = expression.matches(
            in: html,
            range: NSRange(location: 0, length: (html as NSString).length)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges == 5 else { continue }
            let key = (html as NSString).substring(with: match.range(at: 2)).lowercased()
            rendered.replaceCharacters(in: match.range(at: 3), with: Self.escapeHTML(name(for: key)))
        }
        return rendered as String
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
