import Foundation

/// One HTTP request the host is about to perform for a script. Redirects are not followed by
/// the transport; `ScriptedFetchClient` decides, so a redirect off the allow-list never
/// becomes a connection.
public struct ScriptedHTTPRequest: Equatable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval
    public var maxResponseBytes: Int

    public init(
        url: URL, method: String, headers: [String: String], body: Data?, timeout: TimeInterval,
        maxResponseBytes: Int
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }

    /// The `URLRequest` to send. A missing User-Agent is filled in, because some public APIs
    /// reject requests that don't have one.
    public var urlRequest: URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("OpenDock", forHTTPHeaderField: "User-Agent")
        }
        return request
    }
}

/// What one request returned. `failure` is a transport problem (timeout, cancellation, a body
/// over the cap); an HTTP error status is a response, and the script sees it.
public struct ScriptedHTTPResponse: Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public var failure: String?

    public init(status: Int, headers: [String: String], body: Data, failure: String? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.failure = failure
    }
}

/// Performs a single request and does not follow redirects. A 3xx comes back as a response.
public protocol ScriptedHTTPTransport: Sendable {
    func send(_ request: ScriptedHTTPRequest) async -> ScriptedHTTPResponse
}

/// What to do with a 3xx response.
public enum ScriptedRedirect: Equatable, Sendable {
    /// Not a redirect the client follows. The script sees the response.
    case none
    /// Request `url` next. 301, 302 and 303 become GET with no body; 307 and 308 keep both.
    case follow(URL, method: String, body: Data?)
    /// The next URL isn't on the allow-list. The client must not request it.
    case denied(ScriptedFetchDenial)
}

/// The rules around one `opendock.fetch`: https only, GET or POST, declared hosts, a size cap,
/// and redirects that stay on the list.
public enum ScriptedFetchPolicy {
    /// Headers a script can't set. The host owns the connection.
    public static let blockedHeaders: Set<String> = ["host", "content-length", "transfer-encoding", "connection"]

    public static let redirectStatuses: Set<Int> = [301, 302, 303, 307, 308]

    /// Checks the request before any connection. A denied host throws `networkDenied`.
    public static func validate(
        url: URL, method: String, body: Data?, patterns: [String], limits: ScriptedWidgetLimits
    ) throws(ScriptedWidgetError) {
        guard method == "GET" || method == "POST" else {
            throw .fetchFailed("fetch only supports GET and POST.")
        }
        if method == "GET", body != nil {
            throw .fetchFailed("GET can't send a body.")
        }
        if let body, body.count > limits.maxFetchBytes {
            throw .fetchFailed("the request is \(body.count) bytes; the most allowed is \(limits.maxFetchBytes).")
        }
        if let denial = ScriptedHostAllowList.denial(of: url, patterns: patterns) {
            throw error(for: denial)
        }
    }

    /// Drops headers the host owns. Names are compared case-insensitively.
    public static func filteredHeaders(_ headers: [String: String]) -> [String: String] {
        headers.filter { !blockedHeaders.contains($0.key.lowercased()) }
    }

    /// Resolves a redirect, or `.none` when `status` isn't one we follow.
    public static func redirect(
        status: Int, location: String?, from current: URL, method: String, body: Data?, patterns: [String]
    ) -> ScriptedRedirect {
        guard redirectStatuses.contains(status) else { return .none }
        guard let location, let next = URL(string: location, relativeTo: current)?.absoluteURL, next.scheme != nil
        else { return .denied(.missingHost) }
        if let denial = ScriptedHostAllowList.denial(of: next, patterns: patterns) {
            return .denied(denial)
        }
        if status == 307 || status == 308 {
            return .follow(next, method: method, body: body)
        }
        return .follow(next, method: "GET", body: nil)
    }

    static func error(for denial: ScriptedFetchDenial) -> ScriptedWidgetError {
        if let host = denial.host { return .networkDenied(host: host) }
        return .fetchFailed(denial.message)
    }
}

/// The response `opendock.fetch` resolves to, before the script's `text()` and `json()`.
public struct ScriptedFetchResponse: Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// JSON the engine hands to JavaScript: status, lowercased headers, and the body as text.
    public func payload() throws(ScriptedWidgetError) -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            throw .fetchFailed("the response isn't UTF-8 text.")
        }
        let object: [String: Any] = ["status": status, "headers": headers, "body": text]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let encoded = String(data: data, encoding: .utf8)
        else { throw .fetchFailed("the response couldn't be read.") }
        return encoded
    }
}

/// Runs a fetch: allow-list, then the transport, then redirects that stay on the list.
public struct ScriptedFetchClient: Sendable {
    public var transport: any ScriptedHTTPTransport
    public var limits: ScriptedWidgetLimits
    public var patterns: [String]

    public init(transport: any ScriptedHTTPTransport, limits: ScriptedWidgetLimits, patterns: [String]) {
        self.transport = transport
        self.limits = limits
        self.patterns = patterns
    }

    public func fetch(
        url: URL, method: String, headers: [String: String], body: Data?
    ) async throws(ScriptedWidgetError) -> ScriptedFetchResponse {
        var url = url
        var method = method.uppercased()
        var body = body
        let headers = ScriptedFetchPolicy.filteredHeaders(headers)
        for hop in 0 ... limits.maxRedirects {
            try ScriptedFetchPolicy.validate(url: url, method: method, body: body, patterns: patterns, limits: limits)
            let response = await transport.send(
                ScriptedHTTPRequest(
                    url: url, method: method, headers: headers, body: body, timeout: limits.fetchTimeout,
                    maxResponseBytes: limits.maxFetchBytes))
            if let failure = response.failure { throw .fetchFailed(failure) }
            switch ScriptedFetchPolicy.redirect(
                status: response.status, location: response.headers["location"], from: url, method: method, body: body,
                patterns: patterns)
            {
            case .none:
                guard response.body.count <= limits.maxFetchBytes else {
                    throw .fetchFailed(
                        "the response is \(response.body.count) bytes; the most allowed is \(limits.maxFetchBytes).")
                }
                return ScriptedFetchResponse(status: response.status, headers: response.headers, body: response.body)
            case let .denied(denial):
                throw ScriptedFetchPolicy.error(for: denial)
            case let .follow(next, nextMethod, nextBody):
                if hop == limits.maxRedirects {
                    throw .fetchFailed("the response was redirected more than \(limits.maxRedirects) times.")
                }
                url = next
                method = nextMethod
                body = nextBody
            }
        }
        throw .fetchFailed("the response was redirected more than \(limits.maxRedirects) times.")
    }
}

/// `URLSession` transport. Redirects are not followed: the delegate returns nil, and the 3xx
/// response comes back for `ScriptedFetchClient` to judge. The body is capped while it
/// downloads.
public struct ScriptedURLSessionTransport: ScriptedHTTPTransport {
    public init() {}

    public func send(_ request: ScriptedHTTPRequest) async -> ScriptedHTTPResponse {
        let delegate = ScriptedFetchDelegate(maxBytes: request.maxResponseBytes)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let response = await delegate.perform(session: session, request: request.urlRequest)
        session.finishTasksAndInvalidate()
        return response
    }
}

/// Collects one task's body and refuses to follow redirects.
final class ScriptedFetchDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var failure: String?
    private var continuation: CheckedContinuation<ScriptedHTTPResponse, Never>?

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func perform(session: URLSession, request: URLRequest) async -> ScriptedHTTPResponse {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        let tooLong: Bool = lock.withLock {
            self.response = http
            guard let length = http?.value(forHTTPHeaderField: "Content-Length"), let bytes = Int(length) else {
                return false
            }
            if bytes > maxBytes {
                failure = "the response is \(bytes) bytes; the most allowed is \(maxBytes)."
                return true
            }
            return false
        }
        completionHandler(tooLong ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let tooBig: Bool = lock.withLock {
            self.data.append(data)
            if self.data.count > maxBytes {
                failure = "the response is larger than \(maxBytes) bytes."
                return true
            }
            return false
        }
        if tooBig { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (result, continuation): (ScriptedHTTPResponse, CheckedContinuation<ScriptedHTTPResponse, Never>?) =
            lock.withLock {
                let continuation = self.continuation
                self.continuation = nil
                if let failure {
                    return (ScriptedHTTPResponse(status: 0, headers: [:], body: Data(), failure: failure), continuation)
                }
                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain, error.code == NSURLErrorTimedOut {
                        return (
                            ScriptedHTTPResponse(
                                status: 0, headers: [:], body: Data(), failure: "the request timed out."),
                            continuation
                        )
                    }
                    if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                        return (
                            ScriptedHTTPResponse(
                                status: 0, headers: [:], body: Data(), failure: "the request was cancelled."),
                            continuation
                        )
                    }
                    return (
                        ScriptedHTTPResponse(
                            status: 0, headers: [:], body: Data(), failure: error.localizedDescription),
                        continuation
                    )
                }
                return (
                    ScriptedHTTPResponse(
                        status: response?.statusCode ?? 0, headers: Self.headers(of: response), body: data),
                    continuation
                )
            }
        continuation?.resume(returning: result)
    }

    private static func headers(of response: HTTPURLResponse?) -> [String: String] {
        guard let response else { return [:] }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String else { continue }
            headers[name.lowercased()] = String(describing: value)
        }
        return headers
    }
}
