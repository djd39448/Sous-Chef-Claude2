//  APIClient.swift
//
//  The actor that owns every HTTP call to the Go backend at
//  `/api/kitchen/*`.
//
//  Depends on:     Foundation (URLSession, URLRequest), Domain (the FoodItem
//                  return type), APIError, APIErrorEnvelope. No SwiftUI.
//  Depended on by: the SousChef app target. Each tab's @Observable model
//                  reads the actor's async methods; views read the models.
//  Why it exists:  dc-03 says "All HTTP access goes through a single
//                  protocol-defined API client backed by URLSession. No
//                  URLSession calls scattered in views or models." This
//                  file is that client. The iOS track plan §3.4 lists the
//                  full method surface; Week 2 ships only the one method
//                  Phase D1 needs (ingredients()). Later weeks extend it.
//
//                  The client is an actor because it owns a URLSession
//                  (a reference type holding cookie/cache state). Methods
//                  are async; callers await across the actor boundary.
//                  The auth-token provider is an `@Sendable` async
//                  closure so the production AuthModel can refresh the
//                  Supabase JWT before returning it without forcing the
//                  caller onto the auth's actor.

import Domain
import Foundation

/// APIClient is the single typed entry point for backend HTTP calls. It
/// builds requests, attaches the Authorization header from the injected
/// provider, validates the HTTP status, decodes the response body, and
/// throws a typed `APIError` on any non-success outcome.
public actor APIClient {
    /// AuthTokenProvider returns the current bearer token, or nil when
    /// the user is not signed in. It is async so production
    /// implementations can refresh an expired JWT before returning.
    /// Sendable so the closure can be stored on an actor.
    public typealias AuthTokenProvider = @Sendable () async -> String?

    /// baseURL is the root of `/api/kitchen/*`. Per the iOS track plan
    /// §3.4 the iOS app passes it at construction time (e.g.
    /// `http://127.0.0.1:8080` for local dev). The full path each
    /// method calls is `baseURL + "/api/kitchen/<resource>"`.
    private let baseURL: URL

    /// session is the URL loader. URLSession is Sendable as of iOS 17;
    /// it can be passed to an actor at construction. Tests inject a
    /// session backed by a custom URLProtocol stub.
    private let session: URLSession

    /// authTokenProvider returns the bearer token to attach. Stored
    /// once at construction and called per request.
    private let authTokenProvider: AuthTokenProvider

    /// decoder is the single JSONDecoder configured per contract:
    /// ISO 8601 dates (§3.2). Reused across calls.
    private let decoder: JSONDecoder

    /// init constructs an APIClient bound to a base URL and an auth
    /// provider. The default `URLSession` is `.shared`; tests pass a
    /// custom session that uses a URLProtocol stub.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: @escaping AuthTokenProvider
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authTokenProvider = authTokenProvider
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Public surface

    /// IngredientsResponse mirrors the contract §5.5 envelope:
    /// `{ "ingredients": [<food_item>] }`. Nested so the public surface
    /// (`ingredients()`) returns the unwrapped array.
    private struct IngredientsResponse: Decodable {
        let ingredients: [FoodItem]
    }

    /// ingredients returns the user's CFO inventory rows. Per contract
    /// §5.5 / ADR-0009, the server returns only rows with
    /// `usage_context.role = "inventory"` and `inventory_state.status
    /// != "out"`. The client does no further filtering.
    public func ingredients() async throws -> [FoodItem] {
        let request = try await buildRequest(path: "/api/kitchen/ingredients", method: "GET")
        let envelope: IngredientsResponse = try await send(request)
        return envelope.ingredients
    }

    // MARK: - Private plumbing

    /// buildRequest assembles a URLRequest for the given path and
    /// method, attaches the bearer token, and sets the Accept header.
    /// Throws `unauthorized` immediately (without going to the wire)
    /// when the provider returns nil — per the iOS track plan §3.4 and
    /// the work-prompt instructions for Week 2.
    private func buildRequest(path: String, method: String) async throws -> URLRequest {
        guard let token = await authTokenProvider() else {
            throw APIError.unauthorized(envelope: nil)
        }
        guard let url = URL(string: path, relativeTo: baseURL) else {
            // baseURL + a hardcoded path should always resolve; if
            // construction fails the base URL was malformed at init.
            throw APIError.unexpectedStatus(0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// send executes a URLRequest and decodes its body as `T` on
    /// success. Throws the contract-mapped `APIError` on any non-2xx
    /// outcome.
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await performRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpectedStatus(0)
        }
        if (200 ..< 300).contains(http.statusCode) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch let error as DecodingError {
                throw APIError.decoding(error)
            }
        }
        throw mapNonSuccess(status: http.statusCode, data: data)
    }

    /// performRequest centralises the URLSession call so the URLError
    /// translation lives in exactly one place. dc-03 "Convert errors
    /// explicitly at layer boundaries" applies here: URLError surfaces
    /// only through APIError.transport.
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            // URLSession is documented to throw URLError; if anything
            // else surfaces, wrap it in a synthetic URLError so the
            // caller still sees a transport case rather than an opaque
            // Error.
            throw APIError.transport(URLError(.unknown))
        }
    }

    /// mapNonSuccess turns an HTTP status code + body into the matching
    /// APIError case. Lives as its own helper so `send` stays under the
    /// SwiftLint cyclomatic-complexity ceiling and so the status-to-
    /// case mapping is testable in isolation if future cases land.
    private func mapNonSuccess(status: Int, data: Data) -> APIError {
        switch status {
        case 400:
            .badRequest(envelope: decodeEnvelope(data: data, fallbackCode: "bad_request"))
        case 401:
            .unauthorized(envelope: decodeEnvelope(data: data, fallbackCode: "unauthorized"))
        case 403:
            .forbidden(envelope: decodeEnvelope(data: data, fallbackCode: "forbidden"))
        case 404:
            .notFound(envelope: decodeEnvelope(data: data, fallbackCode: "not_found"))
        case 500 ..< 600:
            .serverError(envelope: decodeEnvelope(data: data, fallbackCode: "internal_error"))
        default:
            .unexpectedStatus(status)
        }
    }

    /// decodeEnvelope decodes the contract §3.5 error envelope from a
    /// non-2xx body. If the body is empty or malformed the call site
    /// still gets a usable envelope built from the fallback code — the
    /// UI is never left without something to render.
    private func decodeEnvelope(data: Data, fallbackCode: String) -> APIErrorEnvelope {
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            return envelope
        }
        return APIErrorEnvelope(code: fallbackCode, details: nil)
    }
}
