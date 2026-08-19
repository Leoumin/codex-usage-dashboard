import AppKit
import CodexUsageCore
import Foundation
import SwiftUI
import WidgetKit

struct LimitWindow: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct UsageLimit: Identifiable, Sendable {
    let id: String
    let title: String
    let windows: [LimitWindow]
}

struct ResetCredit: Identifiable, Sendable {
    let id: String
    let title: String
    let expiresAt: Date?
}

struct DashboardSnapshot: Sendable {
    var limits: [UsageLimit] = []
    var resetCreditCount: Int?
    var resetCredits: [ResetCredit] = []
    var fetchedAt = Date()
    var credentialSynced = false
    var error: String?
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot()
    @Published var isLoading = false

    func refresh() {
        isLoading = true
        Task.detached {
            let snapshot = DashboardFetcher.fetch()
            await MainActor.run {
                self.snapshot = snapshot
                self.isLoading = false
            }
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex 用量")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(model.isLoading ? "正在刷新" : model.snapshot.credentialSynced ? "60 秒更新 · iCloud 已同步" : "每 60 秒自动更新")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.snapshot.fetchedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                IconButton(systemName: "arrow.clockwise", disabled: model.isLoading) {
                    model.refresh()
                }
                IconButton(systemName: "xmark.circle") {
                    dismissDashboard()
                }
            }

            if model.snapshot.limits.isEmpty {
                Text(model.isLoading ? "读取中..." : "暂无用量数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.snapshot.limits) { limit in
                        LimitCard(limit: limit)
                    }
                }
            }

            Divider().opacity(0.6)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("重置次数")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(model.snapshot.resetCreditCount ?? model.snapshot.resetCredits.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if model.snapshot.resetCredits.isEmpty {
                    Text("暂无可用到期明细")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.snapshot.resetCredits) { credit in
                        HStack(alignment: .firstTextBaseline) {
                            Text(formatResetCreditTitle(credit.title))
                                .lineLimit(1)
                                .foregroundStyle(.primary.opacity(0.86))
                            Spacer()
                            Text(formatDate(credit.expiresAt))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.system(size: 12))
                    }
                }
            }

            if let error = model.snapshot.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 180, height: 180)
                        .blur(radius: 34)
                        .offset(x: -80, y: -120)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
        }
    }
}

struct LimitCard: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(limit.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(limit.windows.first?.remainingPercent.rounded() ?? 0))%")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ForEach(limit.windows) { window in
                UsageRow(window: window)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
    }
}

struct UsageRow: View {
    let window: LimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("剩余 \(Int(window.remainingPercent.rounded()))%")
                    .monospacedDigit()
                Text(formatDate(window.resetsAt))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            ProgressView(value: window.remainingPercent, total: 100)
                .tint(window.remainingPercent < 20 ? .red : .accentColor)
                .scaleEffect(x: 1, y: 0.72, anchor: .center)
        }
    }
}

struct IconButton: View {
    let systemName: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

enum DashboardFetcher {
    static func fetch() -> DashboardSnapshot {
        var snapshot = DashboardSnapshot()
        var errors: [String] = []
        let credential: CodexCredential

        do {
            credential = try loadCredential()
        } catch {
            snapshot.error = "凭证读取失败：\(short(error))"
            snapshot.fetchedAt = Date()
            return snapshot
        }

        do {
            try syncCredential(credential)
            snapshot.credentialSynced = true
        } catch {
            errors.append("iCloud 同步失败：\(short(error))")
        }

        do {
            let usageData = try readBackendJSON("/backend-api/wham/usage", accessToken: credential.accessToken)
            snapshot.limits = parseUsage(usageData)
            snapshot.resetCreditCount = parseUsageResetCreditCount(usageData)
        } catch {
            errors.append("用量读取失败：\(short(error))")
        }

        do {
            let creditData = try readBackendJSON("/backend-api/wham/rate-limit-reset-credits", accessToken: credential.accessToken)
            let parsed = parseResetCredits(creditData)
            snapshot.resetCredits = parsed.credits
            snapshot.resetCreditCount = parsed.count
        } catch {
            errors.append("到期时间读取失败：\(short(error))")
        }

        snapshot.fetchedAt = Date()
        snapshot.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
        return snapshot
    }

    static var keychainAccessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CodexUsageKeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.contains("$(") else { return nil }
        return value
    }

    static func loadCredential() throws -> CodexCredential {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        return try CodexAuthFile.read(data: Data(contentsOf: authURL))
    }

    static func syncCredential(_ credential: CodexCredential? = nil) throws {
        let credential = try credential ?? loadCredential()
        let store = KeychainCredentialStore(accessGroup: keychainAccessGroup)
        if let stored = try? store.load(), stored == credential { return }
        try store.save(credential)
    }

    static func refreshWidget() throws {
        try syncCredential()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func readBackendJSON(_ endpoint: String, accessToken: String) throws -> [String: Any] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-usage-hud-\(UUID().uuidString).curlrc")
        let config = """
        url = "https://chatgpt.com\(endpoint)"
        header = "Authorization: Bearer \(accessToken)"
        header = "Accept: application/json"
        silent
        show-error
        location
        max-time = 25
        """
        FileManager.default.createFile(
            atPath: tempURL.path,
            contents: Data(config.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var arguments = ["--config", tempURL.path, "--write-out", "\n__HTTP_STATUS:%{http_code}"]
        if let proxy = resolveProxyURL() {
            arguments += ["--proxy", proxy]
        }
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let parts = text.components(separatedBy: "\n__HTTP_STATUS:")
        let body = parts.first ?? ""
        let status = Int(parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        guard process.terminationStatus == 0, (200..<300).contains(status) else {
            if process.terminationStatus == 28 {
                throw FetchError.message("连接超时：未连到 ChatGPT，检查系统代理")
            }
            throw FetchError.message("HTTP \(status == 0 ? Int(process.terminationStatus) : status)")
        }
        guard let data = body.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError.message("invalid credit JSON")
        }
        return object
    }

    static func resolveProxyURL() -> String? {
        let environment = ProcessInfo.processInfo.environment
        for key in ["HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy", "HTTP_PROXY", "http_proxy"] {
            if let value = environment[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        guard let output = try? runProcess("/usr/sbin/scutil", arguments: ["--proxy"]) else { return nil }
        return proxyURL(fromScutilOutput: output)
    }

    static func proxyURL(fromScutilOutput output: String) -> String? {
        let values = Dictionary(uniqueKeysWithValues: output.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })
        if values["HTTPSEnable"] == "1", let host = values["HTTPSProxy"], let port = values["HTTPSPort"] {
            return "http://\(host):\(port)"
        }
        if values["HTTPEnable"] == "1", let host = values["HTTPProxy"], let port = values["HTTPPort"] {
            return "http://\(host):\(port)"
        }
        if values["SOCKSEnable"] == "1", let host = values["SOCKSProxy"], let port = values["SOCKSPort"] {
            return "socks5h://\(host):\(port)"
        }
        return nil
    }

    static func runProcess(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    static func parseUsage(_ object: [String: Any]) -> [UsageLimit] {
        var limits: [UsageLimit] = []
        if let rateLimit = object["rate_limit"] as? [String: Any],
           let limit = parseUsageLimit(id: "codex", title: "Codex", rateLimit: rateLimit) {
            limits.append(limit)
        }
        for item in object["additional_rate_limits"] as? [[String: Any]] ?? [] {
            guard let rateLimit = item["rate_limit"] as? [String: Any] else { continue }
            let id = item["metered_feature"] as? String ?? UUID().uuidString
            let title = item["limit_name"] as? String ?? id
            if let limit = parseUsageLimit(id: id, title: title, rateLimit: rateLimit) {
                limits.append(limit)
            }
        }
        return limits
    }

    static func parseUsageLimit(id: String, title: String, rateLimit: [String: Any]) -> UsageLimit? {
        var windows: [LimitWindow] = []
        if let primary = rateLimit["primary_window"] as? [String: Any] {
            windows.append(parseUsageWindow(primary, fallbackTitle: "5小时"))
        }
        if let secondary = rateLimit["secondary_window"] as? [String: Any] {
            windows.append(parseUsageWindow(secondary, fallbackTitle: "周"))
        }
        return windows.isEmpty ? nil : UsageLimit(id: id, title: title, windows: windows)
    }

    static func parseUsageWindow(_ item: [String: Any], fallbackTitle: String) -> LimitWindow {
        let mins = intValue(item["limit_window_seconds"]).map { $0 / 60 }
        let resetsAt = doubleValue(item["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        return LimitWindow(
            title: mins.map(windowTitle) ?? fallbackTitle,
            usedPercent: doubleValue(item["used_percent"]) ?? 0,
            resetsAt: resetsAt
        )
    }

    static func parseUsageResetCreditCount(_ object: [String: Any]) -> Int? {
        guard let credits = object["rate_limit_reset_credits"] as? [String: Any] else { return nil }
        return intValue(credits["available_count"])
    }

    static func parseResetCredits(_ object: [String: Any]) -> (count: Int?, credits: [ResetCredit]) {
        let credits = (object["credits"] as? [[String: Any]] ?? [])
            .filter { ($0["status"] as? String) == "available" }
            .map { item in
                ResetCredit(
                    id: item["id"] as? String ?? UUID().uuidString,
                    title: item["title"] as? String ?? "Full reset",
                    expiresAt: parseISODate(item["expires_at"] as? String)
                )
            }
            .sorted {
                ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            }
        let count = intValue(object["available_count"])
        return (count, credits)
    }

    static func windowTitle(_ mins: Int) -> String {
        switch mins {
        case 300: return "5小时"
        case 10_080: return "周"
        default:
            return mins >= 60 ? "\(mins / 60)小时" : "\(mins)分钟"
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    static func short(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription {
            return description
        }
        return String(describing: error).replacingOccurrences(of: "message(", with: "").replacingOccurrences(of: ")", with: "")
    }
}

enum FetchError: Error, Sendable {
    case message(String)
}

func parseISODate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

func formatDate(_ date: Date?) -> String {
    guard let date else { return "-" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: date)
}

func formatResetCreditTitle(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "Full reset" {
        return "可用重置"
    }
    if trimmed.hasPrefix("Full reset ") {
        return trimmed.replacingOccurrences(of: "Full reset ", with: "")
    }
    return trimmed.isEmpty ? "可用重置" : trimmed
}

let dismissedSessionURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex/codex-usage-hud-dismissed-session")

@MainActor
func dismissDashboard() {
    try? FileManager.default.createDirectory(
        at: dismissedSessionURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try? "dismissed".write(to: dismissedSessionURL, atomically: true, encoding: .utf8)
    NSApp.terminate(nil)
}

func clearDismissedSession() {
    try? FileManager.default.removeItem(at: dismissedSessionURL)
}

enum SelfTest {
    static func run() {
        let usageJSON = """
        {"rate_limit":{"primary_window":{"used_percent":49,"limit_window_seconds":18000,"reset_at":1783143813},"secondary_window":{"used_percent":64,"limit_window_seconds":604800,"reset_at":1783389305}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_bengalfox","rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_at":1783160314}}}],"rate_limit_reset_credits":{"available_count":4}}
        """
        let creditJSON = """
        {"credits":[{"id":"a","status":"available","title":"Full reset","expires_at":"2026-07-12T02:02:49.252826Z"},{"id":"b","status":"redeemed","title":"Full reset","expires_at":"2026-07-18T00:36:22.524533Z"}],"available_count":1}
        """
        let usage = try! JSONSerialization.jsonObject(with: Data(usageJSON.utf8)) as! [String: Any]
        let limits = DashboardFetcher.parseUsage(usage)
        assert(limits.count == 2)
        assert(limits[0].windows[0].remainingPercent == 51)
        assert(DashboardFetcher.parseUsageResetCreditCount(usage) == 4)
        let credits = DashboardFetcher.parseResetCredits(try! JSONSerialization.jsonObject(with: Data(creditJSON.utf8)) as! [String: Any])
        assert(credits.count == 1)
        assert(credits.credits.count == 1)
        assert(DashboardFetcher.windowTitle(300) == "5小时")
        assert(DashboardFetcher.proxyURL(fromScutilOutput: "HTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 4781\n") == "http://127.0.0.1:4781")
        assert(DashboardFetcher.proxyURL(fromScutilOutput: "SOCKSEnable : 1\nSOCKSProxy : 127.0.0.1\nSOCKSPort : 4781\n") == "socks5h://127.0.0.1:4781")
        assert(formatResetCreditTitle("Full reset") == "可用重置")
        let auth = try! CodexAuthFile.read(data: Data(#"{"last_refresh":"2026-07-16T08:30:00Z","tokens":{"access_token":"access","account_id":"account","refresh_token":"never-sync"}}"#.utf8))
        assert(auth.accessToken == "access")
        assert(!String(decoding: try! JSONEncoder().encode(auth), as: UTF8.self).contains("never-sync"))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DashboardModel()
    var panel: NSPanel?
    var timer: Timer?
    let refreshInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        clearDismissedSession()
        NSApp.setActivationPolicy(.accessory)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 430),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: DashboardView(model: model))
        if let screen = NSScreen.main?.visibleFrame {
            let margin: CGFloat = 18
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(x: screen.maxX - frame.width - margin, y: screen.maxY - frame.height - margin))
        } else {
            panel.center()
        }
        panel.orderFrontRegardless()
        self.panel = panel

        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak model] _ in
            Task { @MainActor in model?.refresh() }
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    SelfTest.run()
    exit(0)
}

if CommandLine.arguments.contains("--sync-credential") {
    do {
        try DashboardFetcher.syncCredential()
        exit(0)
    } catch {
        fputs("Credential sync failed: \(error)\n", stderr)
        exit(1)
    }
}

do {
    try DashboardFetcher.refreshWidget()
    exit(0)
} catch {
    fputs("Widget refresh failed: \(error)\n", stderr)
    exit(1)
}
