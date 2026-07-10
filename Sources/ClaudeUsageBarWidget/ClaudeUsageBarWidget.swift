import WidgetKit
import SwiftUI
import ClaudeUsageBarCore

// WidgetKit widget for Claude Code usage (requirement #4). The timeline provider
// reads the shared snapshot written by the app (SnapshotStore). Implemented by the
// widget agent.
//
// Packaging note: this executable is wrapped into a .appex and embedded in the app
// bundle by Scripts/package_app.sh. Reliable registration/data-sharing may require an
// Xcode build with an App Group — see README.

@main
struct ClaudeUsageBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: SnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: SnapshotStore.read())
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageBarWidget", provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Claude Code usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        // TODO (widget agent): render the snapshot's accounts/windows.
        Text("Claude Usage")
    }
}
