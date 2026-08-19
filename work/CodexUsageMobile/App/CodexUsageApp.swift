import CodexUsageCore
import SwiftUI
import WidgetKit

private let appGroup = "group.com.zhaoxh.codexusage"

@main
@MainActor
struct CodexUsageApp: App {
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup {
            DashboardScreen(model: model)
        }
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var status: String?
    @Published var isRefreshing = false

    private let sampleMode = ProcessInfo.processInfo.arguments.contains("--sample-data")
    private let service = CodexUsageService()
    private let cache = SnapshotStore(suiteName: appGroup)

    init() {
        if sampleMode {
            snapshot = .sample
        } else if let cache {
            snapshot = try? cache.load()
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if sampleMode {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.24)) {
                snapshot = .sample
                status = nil
            }
            return
        }

        do {
            let credential = try KeychainCredentialStore(accessGroup: Self.keychainAccessGroup).load()
            let fresh = try await service.fetch(credential: credential)
            try cache?.save(fresh)
            withAnimation(.easeOut(duration: 0.24)) {
                snapshot = fresh
                status = nil
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            status = (error as? LocalizedError)?.errorDescription ?? "刷新失败"
        }
    }

    private static var keychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "CodexUsageKeychainAccessGroup") as? String
    }
}

struct DashboardScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: DashboardModel
    @State private var creditsExpanded = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    if let snapshot = model.snapshot {
                        Section {
                            usageSection(snapshot)
                            resetSection(snapshot)
                            footer(snapshot)
                        } header: {
                            SummaryHeader(snapshot: snapshot)
                                .background(Color(uiColor: .systemGroupedBackground))
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Codex 用量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                            .animation(.easeInOut(duration: 0.55), value: model.isRefreshing)
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityLabel("刷新用量")
                }
            }
            .refreshable { await model.refresh() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.refresh()
            }
        }
    }

    @ViewBuilder
    private func usageSection(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(snapshot.limits) { limit in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(limit.title, systemImage: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }

                    ForEach(limit.windows) { window in
                        UsageWindowRow(window: window)
                    }
                }
                .padding(16)

                if limit.id != snapshot.limits.last?.id {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func resetSection(_ snapshot: UsageSnapshot) -> some View {
        DisclosureGroup(isExpanded: $creditsExpanded) {
            VStack(spacing: 0) {
                if snapshot.resetCredits.isEmpty {
                    Text("暂无到期明细")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    ForEach(snapshot.resetCredits) { credit in
                        Divider().padding(.leading, 28)
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.teal)
                            Text(credit.title)
                                .lineLimit(1)
                            Spacer()
                            if let expiresAt = credit.expiresAt {
                                Text(compactDate(expiresAt))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .font(.footnote)
                        .padding(.vertical, 11)
                    }
                }
            }
        } label: {
            HStack {
                Label("重置次数", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(snapshot.resetCreditCount)")
                    .font(.custom("Geist", size: 25, relativeTo: .title2).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .tint(.primary)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func footer(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status = model.status {
                Label(status, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 5) {
                Image(systemName: "icloud")
                Text("更新于")
                Text(snapshot.fetchedAt, format: .dateTime.hour().minute())
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: "iphone.and.arrow.forward.inward")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Text(model.status ?? "正在读取用量")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct SummaryHeader: View {
    let snapshot: UsageSnapshot

    private var primary: UsageWindow? { snapshot.primaryWindow }
    private var secondary: UsageWindow? { snapshot.secondaryWindow }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(primary?.title ?? "当前")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int((primary?.remainingPercent ?? 0).rounded()))%")
                    .font(.custom("Geist", size: 52, relativeTo: .largeTitle).weight(.semibold))
                    .foregroundStyle(remainingColor(primary?.remainingPercent ?? 0))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("剩余")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                SummaryMetric(
                    icon: "calendar",
                    title: secondary?.title ?? "本周",
                    value: "\(Int((secondary?.remainingPercent ?? 0).rounded()))%",
                    tint: remainingColor(secondary?.remainingPercent ?? 0)
                )
                Divider()
                SummaryMetric(
                    icon: "arrow.counterclockwise",
                    title: "可用重置",
                    value: "\(snapshot.resetCreditCount)",
                    tint: .primary
                )
            }
            .frame(width: 128)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .top)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SummaryMetric: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.custom("Geist", size: 20, relativeTo: .title3).weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
        }
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.subheadline)
                Spacer()
                Text("剩余 \(Int(window.remainingPercent.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(remainingColor(window.remainingPercent))
                    .monospacedDigit()
                if let resetsAt = window.resetsAt {
                    Text(compactDate(resetsAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(remainingColor(window.remainingPercent))
                .animation(.easeOut(duration: 0.35), value: window.remainingPercent)
        }
    }
}

private func remainingColor(_ value: Double) -> Color {
    if value < 20 { return .red }
    if value < 45 { return .orange }
    return .teal
}

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
