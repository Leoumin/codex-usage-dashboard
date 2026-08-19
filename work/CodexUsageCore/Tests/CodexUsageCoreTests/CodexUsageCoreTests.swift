import XCTest
@testable import CodexUsageCore

final class CodexUsageCoreTests: XCTestCase {
    func testAuthFilePublishesOnlySafeCredentialFields() throws {
        let data = Data(#"{"last_refresh":"2026-07-16T08:30:00Z","tokens":{"access_token":"access-value","account_id":"account-value","refresh_token":"never-sync-this"}}"#.utf8)

        let credential = try CodexAuthFile.read(data: data)
        let encoded = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)

        XCTAssertEqual(credential.accessToken, "access-value")
        XCTAssertEqual(credential.accountID, "account-value")
        XCTAssertEqual(credential.lastRefresh, ISO8601DateFormatter().date(from: "2026-07-16T08:30:00Z"))
        XCTAssertFalse(encoded.contains("never-sync-this"))
        XCTAssertFalse(encoded.contains("refresh_token"))
    }

    func testUsageParserComputesRemainingAndSortsAvailableCredits() throws {
        let usage = Data(#"{"rate_limit":{"primary_window":{"used_percent":49,"limit_window_seconds":18000,"reset_at":1783143813},"secondary_window":{"used_percent":64,"limit_window_seconds":604800,"reset_at":1783389305}},"rate_limit_reset_credits":{"available_count":4}}"#.utf8)
        let credits = Data(#"{"credits":[{"id":"late","status":"available","title":"Full reset","expires_at":"2026-07-18T00:36:22Z"},{"id":"used","status":"redeemed","title":"Full reset","expires_at":"2026-07-17T00:00:00Z"},{"id":"early","status":"available","title":"Full reset","expires_at":"2026-07-17T02:02:49Z"}],"available_count":2}"#.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let snapshot = try UsageParser.snapshot(usageData: usage, creditData: credits, fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.limits.count, 1)
        XCTAssertEqual(snapshot.limits[0].windows.map(\.title), ["5小时", "周"])
        XCTAssertEqual(snapshot.limits[0].windows.map(\.remainingPercent), [51, 36])
        XCTAssertEqual(snapshot.resetCreditCount, 2)
        XCTAssertEqual(snapshot.resetCredits.map(\.id), ["early", "late"])
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testSnapshotStoreRoundTripsSanitizedData() throws {
        let suite = "CodexUsageCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SnapshotStore(defaults: defaults, key: "snapshot")
        let snapshot = UsageSnapshot.sample

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }

    func testUnauthorizedMessageRequestsMacRefresh() {
        XCTAssertEqual(
            CodexUsageError.httpStatus(401).errorDescription,
            "凭证已过期，请在 Mac 上打开 Codex"
        )
    }
}
