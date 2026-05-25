//  StubURLProtocol.swift
//
//  A URLProtocol-based stub for APIClient tests — lets each test enqueue
//  a single canned (HTTPURLResponse, Data) pair the next URLSession
//  request will receive.
//
//  Depends on:     Foundation.
//  Depended on by: APIClientIngredientsTests, APIClientAuthTests,
//                  APIClientErrorTests. Lives in the test target only —
//                  no production code links it.
//  Why it exists:  contract §5 + dc-03 say "all HTTP access goes through
//                  a single … client … No URLSession calls scattered in
//                  views or models." The corollary at test time is "no
//                  network during unit tests" — every APIClient test
//                  stubs the wire via a custom URLProtocol that intercepts
//                  every URLRequest the URLSession would otherwise send.
//                  Using URLProtocol (rather than a hand-rolled URLSession
//                  protocol) keeps the production code free of test-only
//                  injection seams — the standard URLSession remains the
//                  type the actor stores.

import Foundation

/// StubURLProtocol is the URLProtocol subclass URLSession routes every
/// request through when tests install it via
/// `URLSessionConfiguration.protocolClasses`. Tests enqueue a single
/// `Stub` per request via `setStub`; `startLoading` dequeues
/// synchronously and emits the canned response.
///
/// The stub queue lives in a class-level box guarded by an NSLock so
/// the URLProtocol's nonisolated `startLoading` does not need to await
/// across a sending boundary (Swift 6 strict-concurrency would reject
/// capturing `self` and `client` into a Task).
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    // @unchecked Sendable: URLProtocol stores Foundation-owned state
    // (request, cached response, client) which is thread-safe within
    // a single load cycle. We never share an instance across cycles.

    /// Stub bundles the response and body a single request returns.
    struct Stub {
        let response: HTTPURLResponse
        let data: Data
    }

    /// store holds the FIFO of stubs. It is lock-protected (not actor-
    /// backed) so `startLoading` can dequeue synchronously without
    /// spawning a Task — the Task path is disallowed because the
    /// URLProtocolClient is not Sendable.
    private static let store = StubStore()

    /// setStub enqueues one stub for the next URL load. The async
    /// signature is kept so tests using await syntax stay symmetric
    /// with `reset()`; under the hood it is a synchronous lock take.
    static func setStub(_ stub: Stub) async {
        store.enqueue(stub)
    }

    /// reset clears any leftover stub from a prior test.
    static func reset() async {
        store.clear()
    }

    // MARK: - URLProtocol overrides

    // URLProtocol declares canInit and canonicalRequest as `class func`,
    // so the overrides must match — SwiftLint's static-over-final-class
    // suggestion does not apply to required class-method overrides.
    // swiftlint:disable static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    // swiftlint:enable static_over_final_class

    override func startLoading() {
        // Synchronous: no Task hop. URLSession invokes startLoading on
        // its own thread; we call back into the client immediately.
        guard let stub = Self.store.dequeue() else {
            let urlString = request.url?.absoluteString ?? "<no url>"
            let error = URLError(.unknown, userInfo: [
                NSLocalizedDescriptionKey: "StubURLProtocol: no stub enqueued for \(urlString)",
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // No-op: startLoading completes synchronously.
    }
}

/// StubStore is a class-level lock-protected FIFO of stubs. Marked
/// `@unchecked Sendable` because the NSLock is the manual guarantee
/// per dc-03's banned-without-justification rule on `@unchecked
/// Sendable`.
private final class StubStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stubs: [StubURLProtocol.Stub] = []

    func enqueue(_ stub: StubURLProtocol.Stub) {
        lock.lock()
        defer { lock.unlock() }
        stubs.append(stub)
    }

    func dequeue() -> StubURLProtocol.Stub? {
        lock.lock()
        defer { lock.unlock() }
        guard !stubs.isEmpty else { return nil }
        return stubs.removeFirst()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
    }
}

/// makeStubSession constructs a URLSession that routes every request
/// through StubURLProtocol. Tests build one session per case and pass
/// it into the APIClient init.
func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}
