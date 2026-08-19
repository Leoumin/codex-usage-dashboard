import CodexUsageCore
import SwiftUI
import UIKit
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
    @Published var hasIndependentLogin = false

    private let sampleMode = ProcessInfo.processInfo.arguments.contains("--sample-data")
    private let service = CodexUsageService()
    private let oauth = CodexOAuthService()
    private let cache = SnapshotStore(suiteName: appGroup)

    init() {
        if sampleMode {
            snapshot = .sample
        } else if let cache {
            snapshot = try? cache.load()
        }
        hasIndependentLogin = (try? Self.refreshTokenStore.load()) != nil
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
            let fresh = try await fetchWithAutomaticRefresh()
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

    func requestDeviceCode() async throws -> CodexDeviceCode {
        try await oauth.requestDeviceCode()
    }

    func completeLogin(_ deviceCode: CodexDeviceCode) async throws {
        let tokens = try await oauth.completeDeviceCode(deviceCode)
        try save(tokens)
        hasIndependentLogin = true
        await refresh()
    }

    func disconnectIndependentLogin() {
        try? Self.mobileCredentialStore.delete()
        try? Self.refreshTokenStore.delete()
        hasIndependentLogin = false
    }

    private func fetchWithAutomaticRefresh() async throws -> UsageSnapshot {
        let credential = try loadCredential()
        do {
            return try await service.fetch(credential: credential)
        } catch CodexUsageError.httpStatus(401), CodexUsageError.httpStatus(403) {
            guard let refreshToken = try? Self.refreshTokenStore.load() else {
                throw CodexUsageError.httpStatus(401)
            }
            do {
                let tokens = try await oauth.refresh(
                    refreshToken: refreshToken,
                    accountID: credential.accountID
                )
                try save(tokens)
                return try await service.fetch(credential: tokens.credential)
            } catch CodexUsageError.httpStatus(401), CodexUsageError.httpStatus(403) {
                disconnectIndependentLogin()
                throw CodexUsageError.authorizationExpired
            }
        }
    }

    private func loadCredential() throws -> CodexCredential {
        if let mobile = try? Self.mobileCredentialStore.load() { return mobile }
        return try Self.syncedCredentialStore.load()
    }

    private func save(_ tokens: CodexOAuthTokens) throws {
        try Self.refreshTokenStore.save(tokens.refreshToken)
        try Self.mobileCredentialStore.save(tokens.credential)
    }

    private static var keychainAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "CodexUsageKeychainAccessGroup") as? String
    }

    private static var mobileCredentialStore: KeychainCredentialStore {
        KeychainCredentialStore(
            accessGroup: keychainAccessGroup,
            service: CodexKeychainService.mobileCredential,
            synchronizable: false
        )
    }

    private static var syncedCredentialStore: KeychainCredentialStore {
        KeychainCredentialStore(accessGroup: keychainAccessGroup)
    }

    private static var refreshTokenStore: KeychainSecretStore {
        KeychainSecretStore(service: CodexKeychainService.mobileRefreshToken)
    }
}

struct DashboardScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: DashboardModel
    @State private var creditsExpanded = true
    @State private var showingLogin = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingLogin = true } label: {
                        Image(systemName: model.hasIndependentLogin ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    }
                    .accessibilityLabel(model.hasIndependentLogin ? "手机已登录 Codex" : "登录 Codex")
                }
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
            .sheet(isPresented: $showingLogin) {
                CodexLoginSheet(model: model)
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

private struct CodexLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: DashboardModel
    @State private var deviceCode: CodexDeviceCode?
    @State private var error: String?
    @State private var loginAttempt = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if model.hasIndependentLogin {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                    Text("此 iPhone 已独立登录 Codex")
                        .font(.headline)
                    Button("退出手机登录", role: .destructive) {
                        model.disconnectIndependentLogin()
                        deviceCode = nil
                        error = nil
                        loginAttempt += 1
                    }
                } else if let deviceCode {
                    VStack(spacing: 8) {
                        Text("一次性验证码")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(deviceCode.userCode)
                            .font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button {
                        UIPasteboard.general.string = deviceCode.userCode
                    } label: {
                        Label("复制验证码", systemImage: "doc.on.doc")
                    }
                    Button {
                        openURL(deviceCode.verificationURL)
                    } label: {
                        Label("打开 OpenAI 登录", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    ProgressView("等待授权")
                } else if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        self.error = nil
                        loginAttempt += 1
                    }
                } else {
                    ProgressView("正在创建登录请求")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 300)
            .navigationTitle("登录 Codex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: loginAttempt) {
                guard error == nil, !model.hasIndependentLogin, deviceCode == nil else { return }
                do {
                    let code = try await model.requestDeviceCode()
                    deviceCode = code
                    try await model.completeLogin(code)
                    dismiss()
                } catch is CancellationError {
                    return
                } catch {
                    deviceCode = nil
                    self.error = (error as? LocalizedError)?.errorDescription ?? "登录失败"
                }
            }
        }
        .presentationDetents([.medium])
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
                if let secondary {
                    SummaryMetric(
                        icon: "calendar",
                        title: secondary.title,
                        value: "\(Int(secondary.remainingPercent.rounded()))%",
                        tint: remainingColor(secondary.remainingPercent)
                    )
                    Divider()
                } else if let resetsAt = primary?.resetsAt {
                    SummaryMetric(
                        icon: "clock",
                        title: "下次重置",
                        value: compactDate(resetsAt),
                        tint: .primary
                    )
                    Divider()
                }
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
                    .minimumScaleFactor(0.72)
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
