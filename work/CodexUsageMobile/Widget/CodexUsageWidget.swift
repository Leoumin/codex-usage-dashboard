import CodexUsageCore
import SwiftUI
import WidgetKit

private let widgetKind = "CodexUsageWidget"
private let appGroup = "group.com.zhaoxh.codexusage"

#if os(macOS)
private func widgetSnapshotStore() -> SnapshotStore { SnapshotStore(defaults: .standard) }
#else
private func widgetSnapshotStore() -> SnapshotStore { SnapshotStore(suiteName: appGroup)! }
#endif

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let status: String?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample, status: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: cachedSnapshot() ?? .sample, status: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let completion = TimelineCompletion(completion)
        Task {
            let entry = await refreshedEntry()
            let timeline = Timeline(
                entries: [entry],
                policy: .after(Date().addingTimeInterval(30 * 60))
            )
            await MainActor.run { completion.call(timeline) }
        }
    }

    private func refreshedEntry() async -> UsageEntry {
        let cached = cachedSnapshot()
        do {
            let accessGroup = Bundle.main.object(forInfoDictionaryKey: "CodexUsageKeychainAccessGroup") as? String
            let mobileStore = KeychainCredentialStore(
                accessGroup: accessGroup,
                service: CodexKeychainService.mobileCredential,
                synchronizable: false
            )
            let credential: CodexCredential
            if let mobile = try? mobileStore.load() {
                credential = mobile
            } else {
                credential = try KeychainCredentialStore(accessGroup: accessGroup).load()
            }
            let fresh = try await CodexUsageService().fetch(credential: credential)
            try widgetSnapshotStore().save(fresh)
            return UsageEntry(date: Date(), snapshot: fresh, status: nil)
        } catch {
            return UsageEntry(
                date: Date(),
                snapshot: cached,
                status: (error as? LocalizedError)?.errorDescription ?? "刷新失败"
            )
        }
    }

    private func cachedSnapshot() -> UsageSnapshot? {
        try? widgetSnapshotStore().load()
    }
}

// WidgetKit's callback predates Sendable; the wrapper is invoked only on MainActor.
private final class TimelineCompletion: @unchecked Sendable {
    private let callback: (Timeline<UsageEntry>) -> Void

    init(_ callback: @escaping (Timeline<UsageEntry>) -> Void) {
        self.callback = callback
    }

    func call(_ timeline: Timeline<UsageEntry>) {
        callback(timeline)
    }
}

@main
struct CodexUsageWidgets: WidgetBundle {
    var body: some Widget {
        CodexUsageWidget()
    }
}

struct CodexUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: UsageProvider()) { entry in
            CodexWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    widgetBackground
                }
        }
        .configurationDisplayName("Codex 用量")
        .description("查看剩余用量与重置时间")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CodexWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let primary = snapshot.primaryWindow {
                if family == .systemSmall {
                    SmallUsageView(snapshot: snapshot, primary: primary, status: entry.status)
                } else {
                    MediumUsageView(snapshot: snapshot, primary: primary, status: entry.status)
                }
            } else {
                MissingUsageView(status: entry.status)
            }
        }
    }
}

private struct SmallUsageView: View {
    let snapshot: UsageSnapshot
    let primary: UsageWindow
    let status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Codex 用量", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if status != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(widgetAmber)
                        .accessibilityLabel("显示的是缓存数据")
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(primary.remainingPercent.rounded()))%")
                    .font(.custom("Geist", size: 43, relativeTo: .largeTitle).weight(.semibold))
                    .foregroundStyle(widgetColor(primary.remainingPercent))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(primary.title)剩余")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(widgetMuted)
            }

            UsageProgress(value: primary.remainingPercent)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                Text("\(snapshot.resetCreditCount) 次重置")
                    .fontWeight(.medium)
                Spacer()
                Text(compactTime(snapshot.fetchedAt))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(widgetMuted)
        }
    }
}

private struct MediumUsageView: View {
    let snapshot: UsageSnapshot
    let primary: UsageWindow
    let status: String?

    private var secondary: UsageWindow? { snapshot.secondaryWindow }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text("Codex 用量")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: status == nil ? "icloud" : "exclamationmark.circle.fill")
                    Text(status == nil ? compactTime(snapshot.fetchedAt) : "缓存")
                        .monospacedDigit()
                }
                .foregroundStyle(status == nil ? widgetMuted : widgetAmber)
            }
            .font(.caption2)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(primary.title)剩余")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(widgetMuted)

                    Text("\(Int(primary.remainingPercent.rounded()))%")
                        .font(.custom("Geist", size: 44, relativeTo: .largeTitle).weight(.semibold))
                        .foregroundStyle(widgetColor(primary.remainingPercent))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    UsageProgress(value: primary.remainingPercent)

                    HStack(spacing: 8) {
                        if let reset = primary.resetsAt {
                            Label("\(compactDate(reset)) 重置", systemImage: "clock")
                        }
                        if let secondary {
                            Text("\(secondary.title) \(Int(secondary.remainingPercent.rounded()))%")
                                .foregroundStyle(widgetColor(secondary.remainingPercent))
                        }
                    }
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(widgetMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 78)

                VStack(alignment: .leading, spacing: 4) {
                    Text("可用重置")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(widgetMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(snapshot.resetCreditCount)")
                            .font(.custom("Geist", size: 34, relativeTo: .title).weight(.semibold))
                            .monospacedDigit()
                        Text("次")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(widgetMuted)
                    }
                    .foregroundStyle(.white)
                    Text(nearestExpiry)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(widgetMuted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 94, alignment: .leading)
            }
        }
    }

    private var nearestExpiry: String {
        guard let expiry = snapshot.resetCredits.compactMap(\.expiresAt).min() else { return "暂无到期明细" }
        return "到期 \(compactDate(expiry))"
    }
}

private struct UsageProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(widgetColor(value))
                    .frame(width: geometry.size.width * min(max(value, 0), 100) / 100)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("剩余用量")
        .accessibilityValue("\(Int(value.rounded()))%")
    }
}

private struct MissingUsageView: View {
    let status: String?

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "iphone.and.arrow.forward.inward")
                .font(.title2)
                .foregroundStyle(widgetMuted)
            Text(status ?? "等待 Mac 同步凭证")
                .font(.caption)
                .foregroundStyle(widgetMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func widgetColor(_ value: Double) -> Color {
    if value < 20 { return Color(red: 1, green: 0.35, blue: 0.4) }
    if value < 45 { return widgetAmber }
    return Color(red: 0.18, green: 0.83, blue: 0.75)
}

private let widgetBackground = Color(red: 0.055, green: 0.06, blue: 0.07)
private let widgetMuted = Color.white.opacity(0.58)
private let widgetAmber = Color(red: 1, green: 0.7, blue: 0.28)

private func compactDate(_ date: Date) -> String {
    date.formatted(
        Date.FormatStyle()
            .month(.defaultDigits)
            .day(.defaultDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .locale(Locale(identifier: "zh_CN"))
    )
}

private func compactTime(_ date: Date) -> String {
    date.formatted(
        Date.FormatStyle()
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .locale(Locale(identifier: "zh_CN"))
    )
}
