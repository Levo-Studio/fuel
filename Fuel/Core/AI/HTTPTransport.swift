import Foundation

// MARK: - Transport

/// The one seam between a provider client and the network.
///
/// It exists so the clients can be tested. `FuelTests` must never touch a live
/// endpoint — a test that spends the runner's own credit is not a test — and a
/// `URLProtocol` stub would still leave the clients wired to a global. A
/// protocol-shaped session means a test hands the client a recorded response
/// shape and the client cannot reach the network even if it wanted to.
///
/// Deliberately narrow: one request in, bytes and a status out. Nothing here
/// takes a completion handler, a delegate, or a cache policy, because a
/// provider client has no business configuring any of them.
nonisolated protocol HTTPTransport: Sendable {

    /// Sends `request` and returns the response body together with its HTTP
    /// status.
    ///
    /// Throws only for transport failures — no route to host, timeout,
    /// cancellation. A `4xx` or `5xx` is a successful round trip and comes
    /// back as a status for the caller to map; treating it as a thrown error
    /// here would collapse "no credit" and "no network" into one outcome, and
    /// those are two different screens.
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

// MARK: - A connection the system had already dropped

extension HTTPTransport {

    /// Sends `request`, and sends it once more if the first attempt died with
    /// `NSURLErrorNetworkConnectionLost`.
    ///
    /// **The one transport failure worth a second go, and it is worth one
    /// because of how `URLSession` keeps connections.** A session pools its
    /// HTTP/2 connections and reuses them; a connection that the far end,
    /// or a carrier NAT, has quietly closed while it sat idle still looks
    /// usable, so the next request is written into a socket that is already
    /// gone and comes back as `-1005` without having been delivered. The
    /// symptom is a failure that arrives in seconds, on a device with a
    /// perfectly good connection, roughly whenever a request follows a pause
    /// — which is the shape of a scan-then-scan-again session.
    ///
    /// Nothing else is retried. A refused status is the provider's answer and
    /// repeating it would only cost a second request; a timeout means the
    /// request was very likely delivered; and no route to host will not become
    /// one on a second try.
    ///
    /// **What it costs if the guess is wrong.** `-1005` can in principle
    /// arrive after the provider has already accepted and billed the request,
    /// and then this pays for a second one. That is exactly what the user does
    /// when they tap `Try again` on the failure screen, which is where they
    /// would otherwise be — so the worst case is the cost they were going to
    /// pay anyway, and the best case is that they never see the screen. It is
    /// bounded at one extra attempt, deliberately: an automatic ladder on
    /// someone else's credit is not a decision an app gets to make.
    ///
    /// The cancellation check between the two is not decoration. A request the
    /// user has already backed out of must not buy a second one.
    func sendRetryingALostConnection(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await send(request)
        } catch let error as URLError where error.code == .networkConnectionLost {
            try Task.checkCancellation()
            return try await send(request)
        }
    }
}

// MARK: - Response

/// A provider's answer, reduced to the two things a client reads.
///
/// No headers. Nothing in Fuel's error mapping depends on one, and carrying
/// them would put `Retry-After`, request IDs and the echoed `x-api-key` within
/// reach of any future call site.
nonisolated struct HTTPResponse: Sendable, Equatable {

    var statusCode: Int
    var body: Data

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

// MARK: - URLSession

extension URLSession: HTTPTransport {

    nonisolated func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await data(for: request)

        guard let http = response as? HTTPURLResponse else {
            // Every URL this app builds is https, so a non-HTTP response
            // cannot happen. If it somehow does, it is unusable rather than
            // interesting — the interface offers a retry either way.
            throw AIError.network
        }

        return HTTPResponse(statusCode: http.statusCode, body: data)
    }
}

// MARK: - Shared session

extension URLSession {

    /// The session the app's clients run on — one, shared.
    ///
    /// `static let`, not a computed property. Computed, every client
    /// construction built its own `URLSession`, each with its own delegate
    /// queue and connection pool, and no two scans could reuse a TLS
    /// connection. One session is also what the paragraph below assumes when
    /// it says the caches are off.
    ///
    /// Ephemeral on purpose: **nothing touches disk.** A default
    /// `URLSession` writes its URL cache and its cookies into the app
    /// container, which for Fuel would mean a provider's response — the
    /// model's reading of the user's meal — sitting in a file after the
    /// request is over. The only place a meal's content is written down is its
    /// SwiftData entry. The caches below are belt and braces on top of the
    /// ephemeral configuration, which already keeps everything in memory.
    nonisolated static let fuel: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // A meal scan that has hung for a minute is a failure the user should
        // be told about, not something to keep waiting on behind a spinner.
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()
}
