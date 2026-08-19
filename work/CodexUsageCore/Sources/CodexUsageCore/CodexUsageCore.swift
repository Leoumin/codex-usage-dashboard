import Foundation
import Security

public struct CodexCredential: Codable, Equatable, Sendable {
    public let accessToken: String
    public let accountID: String?
    public let lastRefresh: Date?

    public init(accessToken: String, accountID: String?, lastRefresh: Date?) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.lastRefresh = lastRefresh
    }
}

public enum CodexKeychainService {
    public static let syncedCredential = "com.zhaoxh.codexusage.credentials"
    public static let mobileCredential = "com.zhaoxh.codexusage.mobile.credentials"
    public static let mobileRefreshToken = "com.zhaoxh.codexusage.mobile.refresh-token"
}

public enum CodexAuthFile {
    public static func read(data: Data) throws -> CodexCredential {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            throw CodexUsageError.missingCredential
        }

        return CodexCredential(
            accessToken: accessToken,
            accountID: tokens["account_id"] as? String,
            lastRefresh: parseISODate(object["last_refresh"] as? String)
        )
    }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct UsageLimit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let windows: [UsageWindow]

    public init(id: String, title: String, windows: [UsageWindow]) {
        self.id = id
        self.title = title
        self.windows = windows
    }
}

public struct ResetCredit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let expiresAt: Date?

    public init(id: String, title: String, expiresAt: Date?) {
        self.id = id
        self.title = title
        self.expiresAt = expiresAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let limits: [UsageLimit]
    public let resetCreditCount: Int
    public let resetCredits: [ResetCredit]
    public let fetchedAt: Date

    public init(limits: [UsageLimit], resetCreditCount: Int, resetCredits: [ResetCredit], fetchedAt: Date) {
        self.limits = limits
        self.resetCreditCount = resetCreditCount
        self.resetCredits = resetCredits
        self.fetchedAt = fetchedAt
    }

    public var primaryWindow: UsageWindow? { limits.first?.windows.first }
    public var secondaryWindow: UsageWindow? { limits.first?.windows.dropFirst().first }

    public static let sample = UsageSnapshot(
        limits: [
            UsageLimit(
                id: "codex",
                title: "Codex",
                windows: [
                    UsageWindow(id: "codex-primary", title: "5小时", usedPercent: 34, resetsAt: Date(timeIntervalSince1970: 1_789_110_000)),
                    UsageWindow(id: "codex-secondary", title: "周", usedPercent: 58, resetsAt: Date(timeIntervalSince1970: 1_789_542_000))
                ]
            )
        ],
        resetCreditCount: 3,
        resetCredits: [
            ResetCredit(id: "sample-credit-1", title: "可用重置", expiresAt: Date(timeIntervalSince1970: 1_789_196_400)),
            ResetCredit(id: "sample-credit-2", title: "可用重置", expiresAt: Date(timeIntervalSince1970: 1_789_455_600)),
            ResetCredit(id: "sample-credit-3", title: "可用重置", expiresAt: Date(timeIntervalSince1970: 1_789_801_200))
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_788_999_600)
    )
}

public enum UsageParser {
    public static func snapshot(usageData: Data, creditData: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        guard let usage = try JSONSerialization.jsonObject(with: usageData) as? [String: Any],
              let creditObject = try JSONSerialization.jsonObject(with: creditData) as? [String: Any] else {
            throw CodexUsageError.invalidResponse
        }

        var limits: [UsageLimit] = []
        if let rateLimit = usage["rate_limit"] as? [String: Any],
           let limit = parseLimit(id: "codex", title: "Codex", rateLimit: rateLimit) {
            limits.append(limit)
        }

        for item in usage["additional_rate_limits"] as? [[String: Any]] ?? [] {
            guard let rateLimit = item["rate_limit"] as? [String: Any] else { continue }
            let id = item["metered_feature"] as? String ?? UUID().uuidString
            let title = item["limit_name"] as? String ?? id
            if let limit = parseLimit(id: id, title: title, rateLimit: rateLimit) {
                limits.append(limit)
            }
        }

        guard !limits.isEmpty else { throw CodexUsageError.invalidResponse }

        let resetCredits = (creditObject["credits"] as? [[String: Any]] ?? [])
            .filter { ($0["status"] as? String) == "available" }
            .map { item in
                ResetCredit(
                    id: item["id"] as? String ?? UUID().uuidString,
                    title: resetTitle(item["title"] as? String),
                    expiresAt: parseISODate(item["expires_at"] as? String)
                )
            }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }

        let usageCount = (usage["rate_limit_reset_credits"] as? [String: Any]).flatMap { intValue($0["available_count"]) }
        let resetCount = intValue(creditObject["available_count"]) ?? usageCount ?? resetCredits.count

        return UsageSnapshot(
            limits: limits,
            resetCreditCount: resetCount,
            resetCredits: resetCredits,
            fetchedAt: fetchedAt
        )
    }

    private static func parseLimit(id: String, title: String, rateLimit: [String: Any]) -> UsageLimit? {
        var windows: [UsageWindow] = []
        if let primary = rateLimit["primary_window"] as? [String: Any] {
            windows.append(parseWindow(primary, id: "\(id)-primary", fallbackTitle: "5小时"))
        }
        if let secondary = rateLimit["secondary_window"] as? [String: Any] {
            windows.append(parseWindow(secondary, id: "\(id)-secondary", fallbackTitle: "周"))
        }
        return windows.isEmpty ? nil : UsageLimit(id: id, title: title, windows: windows)
    }

    private static func parseWindow(_ item: [String: Any], id: String, fallbackTitle: String) -> UsageWindow {
        let seconds = intValue(item["limit_window_seconds"])
        let resetsAt = doubleValue(item["reset_at"]).map(Date.init(timeIntervalSince1970:))
        return UsageWindow(
            id: id,
            title: seconds.map(windowTitle) ?? fallbackTitle,
            usedPercent: doubleValue(item["used_percent"]) ?? 0,
            resetsAt: resetsAt
        )
    }

    private static func windowTitle(_ seconds: Int) -> String {
        let minutes = seconds / 60
        switch minutes {
        case 300: return "5小时"
        case 10_080: return "周"
        default: return minutes >= 60 ? "\(minutes / 60)小时" : "\(minutes)分钟"
        }
    }

    private static func resetTitle(_ value: String?) -> String {
        let title = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title == "Full reset" || title.isEmpty { return "可用重置" }
        if title.hasPrefix("Full reset ") { return String(title.dropFirst("Full reset ".count)) }
        return title
    }
}

public struct KeychainCredentialStore: Sendable {
    private let accessGroup: String?
    private let service: String
    private let account: String
    private let synchronizable: Bool

    public init(
        accessGroup: String? = nil,
        service: String = CodexKeychainService.syncedCredential,
        account: String = "codex",
        synchronizable: Bool = true
    ) {
        self.accessGroup = accessGroup
        self.service = service
        self.account = account
        self.synchronizable = synchronizable
    }

    public func save(_ credential: CodexCredential) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(credential)
        let query = baseQuery()
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CodexUsageError.keychain(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw CodexUsageError.keychain(status) }
    }

    public func load() throws -> CodexCredential {
        var query = baseQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw CodexUsageError.missingCredential }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CodexUsageError.keychain(status)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexCredential.self, from: data)
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CodexUsageError.keychain(status)
        }
    }

    private func baseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }
}

public struct KeychainSecretStore: Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String = "codex") {
        self.service = service
        self.account = account
    }

    public func save(_ value: String) throws {
        let query = baseQuery()
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CodexUsageError.keychain(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw CodexUsageError.keychain(status) }
    }

    public func load() throws -> String {
        var query = baseQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw CodexUsageError.missingCredential }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw CodexUsageError.keychain(status)
        }
        return value
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CodexUsageError.keychain(status)
        }
    }

    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
    }
}

public struct SnapshotStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = "codex-usage-snapshot") {
        self.defaults = defaults
        self.key = key
    }

    public init?(suiteName: String, key: String = "codex-usage-snapshot") {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.init(defaults: defaults, key: key)
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        defaults.set(try encoder.encode(snapshot), forKey: key)
    }

    public func load() throws -> UsageSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(UsageSnapshot.self, from: data)
    }
}

public struct CodexUsageService: Sendable {
    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://chatgpt.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetch(credential: CodexCredential) async throws -> UsageSnapshot {
        async let usageData = request(path: "/backend-api/wham/usage", credential: credential)
        async let creditData = request(path: "/backend-api/wham/rate-limit-reset-credits", credential: credential)
        return try await UsageParser.snapshot(usageData: usageData, creditData: creditData)
    }

    private func request(path: String, credential: CodexCredential) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw CodexUsageError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credential.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CodexUsageError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw CodexUsageError.httpStatus(http.statusCode) }
            return data
        } catch let error as CodexUsageError {
            throw error
        } catch {
            throw CodexUsageError.transport
        }
    }
}

public struct CodexDeviceCode: Equatable, Sendable {
    public let verificationURL: URL
    public let userCode: String
    fileprivate let deviceAuthID: String
    fileprivate let interval: TimeInterval
}

public struct CodexOAuthTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let accountID: String?

    public var credential: CodexCredential {
        CodexCredential(accessToken: accessToken, accountID: accountID, lastRefresh: Date())
    }
}

public struct CodexOAuthService: Sendable {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let session: URLSession
    private let issuer: URL

    public init(
        session: URLSession = .shared,
        issuer: URL = URL(string: "https://auth.openai.com")!
    ) {
        self.session = session
        self.issuer = issuer
    }

    public func requestDeviceCode() async throws -> CodexDeviceCode {
        let request = try jsonRequest(
            path: "/api/accounts/deviceauth/usercode",
            body: ["client_id": Self.clientID]
        )
        let data = try await send(request)
        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        guard !response.deviceAuthID.isEmpty, !response.userCode.isEmpty else {
            throw CodexUsageError.invalidResponse
        }
        return CodexDeviceCode(
            verificationURL: issuer.appending(path: "codex/device"),
            userCode: response.userCode,
            deviceAuthID: response.deviceAuthID,
            interval: response.interval
        )
    }

    public func completeDeviceCode(_ deviceCode: CodexDeviceCode) async throws -> CodexOAuthTokens {
        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            let request = try jsonRequest(
                path: "/api/accounts/deviceauth/token",
                body: [
                    "device_auth_id": deviceCode.deviceAuthID,
                    "user_code": deviceCode.userCode
                ]
            )
            do {
                let data = try await send(request)
                let code = try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: data)
                return try await exchangeAuthorizationCode(code)
            } catch CodexUsageError.httpStatus(403), CodexUsageError.httpStatus(404) {
                if deviceCode.interval > 0 {
                    try await Task.sleep(for: .seconds(deviceCode.interval))
                }
            }
        }
        throw CodexUsageError.authorizationExpired
    }

    public func refresh(refreshToken: String, accountID: String?) async throws -> CodexOAuthTokens {
        let request = try jsonRequest(
            path: "/oauth/token",
            body: [
                "client_id": Self.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        )
        let response = try JSONDecoder().decode(TokenResponse.self, from: try await send(request))
        guard let accessToken = response.accessToken, !accessToken.isEmpty else {
            throw CodexUsageError.invalidResponse
        }
        return CodexOAuthTokens(
            accessToken: accessToken,
            refreshToken: response.refreshToken?.nonEmpty ?? refreshToken,
            accountID: extractAccountID(from: response.idToken ?? accessToken) ?? accountID
        )
    }

    private func exchangeAuthorizationCode(_ code: DeviceAuthorizationResponse) async throws -> CodexOAuthTokens {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code.authorizationCode),
            URLQueryItem(name: "redirect_uri", value: issuer.appending(path: "deviceauth/callback").absoluteString),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code_verifier", value: code.codeVerifier)
        ]
        var request = URLRequest(url: issuer.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let response = try JSONDecoder().decode(TokenResponse.self, from: try await send(request))
        guard let accessToken = response.accessToken?.nonEmpty,
              let refreshToken = response.refreshToken?.nonEmpty else {
            throw CodexUsageError.invalidResponse
        }
        return CodexOAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountID: extractAccountID(from: response.idToken ?? accessToken)
        )
    }

    private func jsonRequest(path: String, body: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: issuer.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CodexUsageError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw CodexUsageError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as CodexUsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CodexUsageError.transport
        }
    }

    private func extractAccountID(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = payload["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return (auth["chatgpt_account_id"] as? String)?.nonEmpty
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case usercode
        case interval
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try values.decode(String.self, forKey: .deviceAuthID)
        userCode = try values.decodeIfPresent(String.self, forKey: .userCode)
            ?? values.decode(String.self, forKey: .usercode)
        if let string = try? values.decode(String.self, forKey: .interval) {
            interval = TimeInterval(string) ?? 5
        } else {
            interval = try values.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 5
        }
    }
}

private struct DeviceAuthorizationResponse: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

public enum CodexUsageError: Error, Equatable, LocalizedError, Sendable {
    case missingCredential
    case invalidResponse
    case authorizationExpired
    case httpStatus(Int)
    case keychain(OSStatus)
    case transport

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "等待 Mac 同步凭证"
        case .httpStatus(401), .httpStatus(403):
            return "凭证已过期，请在 App 中登录 Codex"
        case let .httpStatus(status):
            return "读取失败：HTTP \(status)"
        case .invalidResponse:
            return "用量数据格式异常"
        case .authorizationExpired:
            return "登录已超时，请重试"
        case let .keychain(status):
            return "iCloud 凭证读取失败（\(status)）"
        case .transport:
            return "网络连接失败"
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private func parseISODate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}
