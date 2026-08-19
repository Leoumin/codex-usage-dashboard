import XCTest
@testable import CodexUsageCore

final class CodexUsageCoreTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

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

    func testUnauthorizedMessageRequestsPhoneLogin() {
        XCTAssertEqual(
            CodexUsageError.httpStatus(401).errorDescription,
            "凭证已过期，请在 App 中登录 Codex"
        )
    }

    func testDeviceCodeLoginExchangesIndependentTokens() async throws {
        let session = mockSession { request in
            switch request.url?.path {
            case "/api/accounts/deviceauth/usercode":
                XCTAssertEqual(request.httpMethod, "POST")
                return Self.response(
                    request,
                    json: #"{"device_auth_id":"device-1","user_code":"ABCD-EFGH","interval":"0"}"#
                )
            case "/api/accounts/deviceauth/token":
                return Self.response(
                    request,
                    json: #"{"authorization_code":"authorization-code","code_challenge":"challenge","code_verifier":"verifier"}"#
                )
            case "/oauth/token":
                let body = String(decoding: try Self.body(of: request), as: UTF8.self)
                XCTAssertTrue(body.contains("grant_type=authorization_code"))
                XCTAssertTrue(body.contains("code=authorization-code"))
                return Self.response(
                    request,
                    json: #"{"id_token":"eyJhbGciOiJub25lIn0.eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdC0xMjMifX0.signature","access_token":"access-1","refresh_token":"refresh-1"}"#
                )
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return Self.response(request, status: 404, json: "{}")
            }
        }
        let service = CodexOAuthService(session: session, issuer: URL(string: "https://auth.example")!)

        let deviceCode = try await service.requestDeviceCode()
        let tokens = try await service.completeDeviceCode(deviceCode)

        XCTAssertEqual(deviceCode.userCode, "ABCD-EFGH")
        XCTAssertEqual(deviceCode.verificationURL.absoluteString, "https://auth.example/codex/device")
        XCTAssertEqual(tokens.accessToken, "access-1")
        XCTAssertEqual(tokens.refreshToken, "refresh-1")
        XCTAssertEqual(tokens.accountID, "acct-123")
    }

    func testRefreshPersistsRotatedTokenAndKeepsOldTokenWhenOmitted() async throws {
        var responses = [
            #"{"access_token":"access-2","refresh_token":"refresh-2"}"#,
            #"{"access_token":"access-3"}"#
        ]
        let session = mockSession { request in
            XCTAssertEqual(request.url?.path, "/oauth/token")
            let body = try JSONSerialization.jsonObject(with: try Self.body(of: request)) as? [String: String]
            XCTAssertEqual(body?["grant_type"], "refresh_token")
            return Self.response(request, json: responses.removeFirst())
        }
        let service = CodexOAuthService(session: session, issuer: URL(string: "https://auth.example")!)

        let rotated = try await service.refresh(refreshToken: "refresh-1", accountID: "acct-123")
        let retained = try await service.refresh(refreshToken: rotated.refreshToken, accountID: rotated.accountID)

        XCTAssertEqual(rotated.refreshToken, "refresh-2")
        XCTAssertEqual(retained.accessToken, "access-3")
        XCTAssertEqual(retained.refreshToken, "refresh-2")
        XCTAssertEqual(retained.accountID, "acct-123")
    }

    private func mockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }

    private static func body(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
