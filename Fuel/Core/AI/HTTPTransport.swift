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

// MARK: - Streaming

/// The second thing a provider can be asked for: the answer as it is written,
/// rather than once it is finished.
///
/// **A capability beside `send`, not a replacement for it.** An estimate is a
/// single JSON object that is worth nothing until it is complete — a half-read
/// meal is not a smaller meal, it is no meal — so the estimate path and the key
/// check go on using `send` unchanged and gain nothing from a stream. A
/// conversation is the opposite: the sentence is prose, it reads the same
/// arriving as it does arrived, and waiting for the last token to draw the
/// first word is a wait for nothing.
///
/// It refines `HTTPTransport` rather than standing alone because a client that
/// streams also has to be able to ask a plain question — both provider clients
/// check a key and estimate a meal — and a second, unrelated transport property
/// on those types would be a second place a key could be sent from.
nonisolated protocol StreamingHTTPTransport: HTTPTransport {

    /// Sends `request` and returns as soon as the response head has arrived,
    /// with the body still open.
    ///
    /// Throws for the same reasons `send` does and no others: a transport
    /// failure before the head. A `4xx` or `5xx` arrives as a status on the
    /// returned value, with its body still to be read — the caller decides
    /// whether it is worth reading, which for a refusal means bounded and for
    /// anything else means not at all.
    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse
}

// MARK: - A stream whose head never arrived

extension StreamingHTTPTransport {

    /// Opens `request`, and opens it once more if the first attempt died with
    /// `NSURLErrorNetworkConnectionLost`.
    ///
    /// **The same guess as `sendRetryingALostConnection`, and it is a safer one
    /// here rather than a riskier one.** That method's caveat is that `-1005`
    /// can in principle arrive after the provider has already accepted and
    /// billed the request. `stream` returns the moment the response head lands,
    /// so a failure thrown *from it* is a failure before any head — the request
    /// was written into a socket that was already gone. Nothing that had begun
    /// answering can fail this way.
    ///
    /// A connection lost *after* the head is not retried and is not reachable
    /// from here: it surfaces while the caller is iterating the body, which is
    /// a half-written answer rather than an undelivered request. See
    /// `MealChatModel` for what happens to one.
    func streamRetryingALostConnection(_ request: URLRequest) async throws -> HTTPStreamResponse {
        do {
            return try await stream(request)
        } catch let error as URLError where error.code == .networkConnectionLost {
            try Task.checkCancellation()
            return try await stream(request)
        }
    }
}

// MARK: - An answer still arriving

/// A response whose head has arrived and whose body has not.
///
/// **Lines rather than bytes**, because every stream Fuel reads is
/// `text/event-stream` and every event stream is line-oriented. Handing a
/// client raw chunks would mean both provider clients reimplementing the same
/// split, and a test double supplying plausible chunk boundaries rather than a
/// recorded transcript.
///
/// **The split is `ServerSentEventLineSplitter`'s and not `URLSession`'s**, for
/// the reason that type is written out at length: Foundation's own line
/// sequence drops blank lines, and a blank line is this format's dispatch.
///
/// No headers, for the reason `HTTPResponse` carries none.
nonisolated struct HTTPStreamResponse: Sendable {

    var statusCode: Int

    /// The body, one line at a time, with the line breaks already removed.
    /// Finishes when the provider closes the stream, and throws whatever the
    /// connection threw if it dies part-way.
    var lines: AsyncThrowingStream<String, any Error>

    init(statusCode: Int, lines: AsyncThrowingStream<String, any Error>) {
        self.statusCode = statusCode
        self.lines = lines
    }

    /// The body of a refused stream, read only as far as the error mapping can
    /// actually use.
    ///
    /// **Bounded at `AIError.readableErrorBody` for the reason that bound
    /// exists**: a body larger than that is not an error message any provider
    /// writes, and `AIError.from(status:body:provider:)` will not search it. A
    /// refusal whose body is a megabyte of HTML from something in front of the
    /// API would otherwise be a megabyte read, decoded and thrown away.
    ///
    /// Never called for a stream that was accepted, so a successful answer is
    /// never buffered whole — which is the point of streaming it.
    func refusalBody() async -> Data {
        var body = Data()
        do {
            for try await line in lines {
                body.append(contentsOf: line.utf8)
                guard body.count < AIError.readableErrorBody else { break }
            }
        } catch {
            // A refusal whose body did not finish arriving is still a refusal,
            // and the status already says which. Whatever was read stands.
        }
        return body
    }
}

// MARK: - URLSession

extension URLSession: StreamingHTTPTransport {

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

    /// `bytes(for:)` rather than `data(for:)`: it returns once the head has
    /// arrived and leaves the body to be pulled, which is the whole difference
    /// between the two methods on this protocol.
    ///
    /// The bytes are framed into an `AsyncThrowingStream` of lines rather than
    /// handed over as `URLSession.AsyncBytes.AsyncLineSequence`, so
    /// `HTTPStreamResponse` names one concrete type that a test double can also
    /// produce. The inner task is cancelled when the caller stops iterating,
    /// which is what tears the connection down when a message is called off.
    ///
    /// **`ServerSentEventLineSplitter` and not `bytes.lines`.** The convenience
    /// was the bug: Foundation's line sequence discards blank lines, and in
    /// `text/event-stream` the blank line is the dispatch. Read with `.lines`,
    /// every conversation reached the user as "the answer did not come back in
    /// a form Fuel could read", because none of it was ever delivered. That
    /// type says the whole of it.
    nonisolated func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        let (bytes, response) = try await self.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIError.network
        }

        return HTTPStreamResponse(
            statusCode: http.statusCode,
            lines: AsyncThrowingStream { continuation in
                let pump = Task {
                    do {
                        var splitter = ServerSentEventLineSplitter()
                        for try await byte in bytes {
                            if let line = try splitter.append(byte) {
                                continuation.yield(line)
                            }
                        }
                        if let last = splitter.flush() {
                            continuation.yield(last)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in pump.cancel() }
            }
        )
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
