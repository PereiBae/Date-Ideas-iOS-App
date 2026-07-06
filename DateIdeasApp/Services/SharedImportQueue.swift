import Foundation

enum SharedImportQueue {
    static let appGroupIdentifier = "group.com.brandonpereira.dateideas"
    private static let key = "dateIdeas.sharedImportURLs"

    static func enqueue(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        var values = defaults.stringArray(forKey: key) ?? []
        values.append(url.absoluteString)
        defaults.set(values, forKey: key)
    }

    static func dequeueAll() -> [URL] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return [] }
        let values = defaults.stringArray(forKey: key) ?? []
        defaults.removeObject(forKey: key)
        return values.compactMap(URL.init(string:))
    }

    static func pendingCount() -> Int {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return 0 }
        return defaults.stringArray(forKey: key)?.count ?? 0
    }

    static func dequeueFirst() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }
        var values = defaults.stringArray(forKey: key) ?? []

        while !values.isEmpty {
            let first = values.removeFirst()
            if let url = URL(string: first) {
                defaults.set(values, forKey: key)
                return url
            }
        }

        defaults.removeObject(forKey: key)
        return nil
    }
}

