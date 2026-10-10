import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted fetch policy")
struct FetchPolicyTests {
    private let patterns = ["api.github.com", "*.open-meteo.com"]
    private let limits = ScriptedWidgetLimits.default

    @Test func allowsGETAndPOSTToADeclaredHost() throws {
        let url = URL(string: "https://api.github.com/repos/newyorkcompute/opendock")!
        try ScriptedFetchPolicy.validate(url: url, method: "GET", body: nil, patterns: patterns, limits: limits)
        try ScriptedFetchPolicy.validate(
            url: url, method: "POST", body: Data("{}".utf8), patterns: patterns, limits: limits)
    }

    @Test func rejectsTheMethodTheBodyAndUndeclaredHostsBeforeAnyConnection() {
        let url = URL(string: "https://api.github.com/")!
        #expect(throws: ScriptedWidgetError.fetchFailed("fetch only supports GET and POST.")) {
            try ScriptedFetchPolicy.validate(url: url, method: "PUT", body: nil, patterns: patterns, limits: limits)
        }
        #expect(throws: ScriptedWidgetError.fetchFailed("GET can't send a body.")) {
            try ScriptedFetchPolicy.validate(
                url: url, method: "GET", body: Data([1]), patterns: patterns, limits: limits)
        }
        #expect(throws: ScriptedWidgetError.networkDenied(host: "evil.example")) {
            try ScriptedFetchPolicy.validate(
                url: URL(string: "https://evil.example/x")!, method: "GET", body: nil, patterns: patterns,
                limits: limits)
        }
        #expect(throws: ScriptedWidgetError.fetchFailed("Fetch URLs have to be https.")) {
            try ScriptedFetchPolicy.validate(
                url: URL(string: "http://api.github.com/")!, method: "GET", body: nil, patterns: patterns,
                limits: limits)
        }
    }

    @Test func rejectsABodyOverTheCap() {
        var limits = ScriptedWidgetLimits()
        limits.maxFetchBytes = 4
        #expect(throws: ScriptedWidgetError.fetchFailed("the request is 5 bytes; the most allowed is 4.")) {
            try ScriptedFetchPolicy.validate(
                url: URL(string: "https://api.github.com/")!, method: "POST", body: Data("hello".utf8),
                patterns: patterns, limits: limits)
        }
    }

    @Test func dropsHeadersTheHostOwns() {
        let headers = ScriptedFetchPolicy.filteredHeaders([
            "Accept": "application/json", "Host": "evil.example", "Content-Length": "9", "X-Name": "OpenDock",
        ])
        #expect(headers == ["Accept": "application/json", "X-Name": "OpenDock"])
    }

    @Test func followsARedirectThatStaysOnTheList() {
        let current = URL(string: "https://api.github.com/v1")!
        guard
            case let .follow(next, method, body) = ScriptedFetchPolicy.redirect(
                status: 302, location: "/v2", from: current, method: "POST", body: Data("x".utf8), patterns: patterns)
        else {
            Issue.record("expected a followed redirect")
            return
        }
        #expect(next == URL(string: "https://api.github.com/v2"))
        #expect(method == "GET")
        #expect(body == nil)

        guard
            case let .follow(kept, keptMethod, keptBody) = ScriptedFetchPolicy.redirect(
                status: 307, location: "https://api.open-meteo.com/v1", from: current, method: "POST",
                body: Data("x".utf8), patterns: patterns)
        else {
            Issue.record("expected a 307 to keep the request")
            return
        }
        #expect(kept.host == "api.open-meteo.com")
        #expect(keptMethod == "POST")
        #expect(keptBody == Data("x".utf8))
    }

    @Test func refusesARedirectOffTheList() {
        let current = URL(string: "https://api.github.com/")!
        #expect(
            ScriptedFetchPolicy.redirect(
                status: 302, location: "https://evil.example/steal", from: current, method: "GET", body: nil,
                patterns: patterns) == .denied(.hostNotAllowed("evil.example")))
        #expect(
            ScriptedFetchPolicy.redirect(
                status: 301, location: "http://api.github.com/plain", from: current, method: "GET", body: nil,
                patterns: patterns) == .denied(.notHTTPS))
        #expect(
            ScriptedFetchPolicy.redirect(
                status: 200, location: "https://evil.example/", from: current, method: "GET", body: nil,
                patterns: patterns) == .none)
    }

    @Test func clientNeverRequestsADeniedHost() async {
        let transport = FakeTransport { _ in
            Issue.record("the transport was called for a denied host")
            return ScriptedHTTPResponse(status: 200, headers: [:], body: Data())
        }
        let client = ScriptedFetchClient(transport: transport, limits: limits, patterns: patterns)
        let error = await failure {
            _ = try await client.fetch(
                url: URL(string: "https://evil.example/")!, method: "GET", headers: [:], body: nil)
        }
        #expect(error == .networkDenied(host: "evil.example"))
        #expect(transport.calls.isEmpty)
    }

    @Test func clientDoesNotFollowARedirectOffTheList() async throws {
        let transport = FakeTransport { request in
            #expect(request.url.host == "api.github.com")
            return ScriptedHTTPResponse(
                status: 302, headers: ["location": "https://evil.example/nope"], body: Data("go away".utf8))
        }
        let client = ScriptedFetchClient(transport: transport, limits: limits, patterns: patterns)
        let error = await failure {
            _ = try await client.fetch(
                url: URL(string: "https://api.github.com/start")!, method: "GET", headers: [:], body: nil)
        }
        #expect(error == .networkDenied(host: "evil.example"))
        #expect(transport.calls.count == 1)
    }

    @Test func clientFollowsAnOnListRedirectAndReturnsTheBody() async throws {
        let transport = FakeTransport { request in
            if request.url.path == "/start" {
                return ScriptedHTTPResponse(
                    status: 302, headers: ["location": "https://api.open-meteo.com/v1/forecast"], body: Data())
            }
            return ScriptedHTTPResponse(
                status: 200, headers: ["content-type": "application/json"], body: Data(#"{"ok":true}"#.utf8))
        }
        let client = ScriptedFetchClient(transport: transport, limits: limits, patterns: patterns)
        let response = try await client.fetch(
            url: URL(string: "https://api.github.com/start")!, method: "POST", headers: ["Host": "evil.example"],
            body: Data("{}".utf8))
        #expect(response.status == 200)
        #expect(String(decoding: response.body, as: UTF8.self) == #"{"ok":true}"#)
        #expect(transport.calls.count == 2)
        #expect(transport.calls[0].method == "POST")
        #expect(transport.calls[0].headers["Host"] == nil)
        #expect(transport.calls[1].method == "GET")
        #expect(transport.calls[1].url.host == "api.open-meteo.com")
        #expect(transport.calls[1].body == nil)
    }

    private func failure(_ body: () async throws -> Void) async -> ScriptedWidgetError? {
        do {
            try await body()
            return nil
        } catch let error as ScriptedWidgetError {
            return error
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }
}

/// Records the requests it was given and answers with `handler`.
final class FakeTransport: ScriptedHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ScriptedHTTPRequest] = []
    private let handler: @Sendable (ScriptedHTTPRequest) -> ScriptedHTTPResponse

    init(_ handler: @escaping @Sendable (ScriptedHTTPRequest) -> ScriptedHTTPResponse) {
        self.handler = handler
    }

    var calls: [ScriptedHTTPRequest] { lock.withLock { recorded } }

    func send(_ request: ScriptedHTTPRequest) async -> ScriptedHTTPResponse {
        lock.withLock { recorded.append(request) }
        return handler(request)
    }
}
