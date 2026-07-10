import Foundation

/// Shared persistence for the latest snapshot, so the widget can read what the app
/// last fetched. Written to Application Support (both processes run as the same user).
///
/// Note: a sandboxed widget extension would need an App Group container instead; this
/// file-based approach works for the non-sandboxed ad-hoc build.
public enum SnapshotStore {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
    }

    public static var fileURL: URL { directory.appendingPathComponent("snapshot.json") }

    public static func write(_ snapshot: UsageSnapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort; a failed write just means the widget shows the previous snapshot.
        }
    }

    public static func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
