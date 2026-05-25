//  APIError.swift
//
//  The typed error set every APIClient method throws.
//
//  Depends on:     Foundation and APIErrorEnvelope (for the 5xx case).
//  Depended on by: APIClient (every method throws this); the iOS app's
//                  views (catch the case to render an error state).
//  Why it exists:  dc-03 says "Convert errors explicitly at layer
//                  boundaries — a low-level networking error never leaks
//                  into UI code." The networking layer surfaces only
//                  these well-defined cases: each maps to a user-visible
//                  outcome (unauthorized → sign in; not_found → empty
//                  state; transport → network warning; decoding →
//                  contract-mismatch alert). Per the iOS track plan
//                  §3.4 each is keyed on the contract's normative error
//                  codes (`contract/contract.md` §3.5).
//
//                  The case set is finite and curated; the matching
//                  `catch` at the call site is exhaustive without a
//                  default branch when the call site uses
//                  `throws(APIError)` typed-throws. v1 stays untyped to
//                  keep call sites compatible with the Auth library's
//                  Supabase-SDK errors which may be propagated unchanged.

import Foundation

/// APIError is the curated set the APIClient throws. Per dc-03 it
/// conforms to `LocalizedError` so the UI gets a readable description
/// without having to switch over the cases at every render site.
public enum APIError: Error, Sendable {
    /// unauthorized — the server returned 401 (contract §2.3:
    /// `missing_authorization`, `malformed_token`, `invalid_token`,
    /// `expired_token`, `wrong_issuer`). The envelope is captured so a
    /// UI surface can show "your session expired" vs "no token sent"
    /// when it cares. The envelope is optional because the client also
    /// throws `unauthorized` without going to the wire when the auth-
    /// token provider returns nil (no envelope to capture).
    case unauthorized(envelope: APIErrorEnvelope?)

    /// forbidden — the server returned 403 (contract §2.3:
    /// `not_owner`). The envelope is always present in this case.
    case forbidden(envelope: APIErrorEnvelope)

    /// notFound — the server returned 404. Per contract §2.3 the
    /// server emits 404 for both "row doesn't exist" and "row exists
    /// but belongs to another user" — the client cannot distinguish
    /// and must not try.
    case notFound(envelope: APIErrorEnvelope)

    /// badRequest — the server returned 400 with a structured envelope
    /// (e.g. `unknown_field`, `week_start_not_monday`, `invalid_field`).
    /// Not in the original spec list but the only sensible mapping for
    /// 4xx codes the client did not anticipate (e.g. validation rejects).
    case badRequest(envelope: APIErrorEnvelope)

    /// serverError — the server returned 5xx. Contract §3.5 says the
    /// envelope is `internal_error` for anything else; the iOS UI
    /// shows a generic "something went wrong" affordance with retry.
    case serverError(envelope: APIErrorEnvelope)

    /// transport — the URL load failed before a response arrived
    /// (network down, DNS, TLS, request timeout). The underlying
    /// URLError preserves the OS-level reason.
    case transport(URLError)

    /// decoding — the response body did not match the expected shape.
    /// This is a contract-drift signal: it indicates the server now
    /// emits a shape the iOS Codable types do not understand. The
    /// captured DecodingError carries the path to the failing field.
    case decoding(DecodingError)

    /// unexpectedStatus — the response carried a status code outside
    /// the contract's documented set (i.e. not 2xx, not 4xx
    /// 401/403/404/400, not 5xx). Captured so the call site can log
    /// the surprise; the UI shows a generic error.
    case unexpectedStatus(Int)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unauthorized(envelope):
            "Session expired or not signed in. (\(envelope?.code ?? "no_token"))"
        case let .forbidden(envelope):
            "Access denied. (\(envelope.code))"
        case let .notFound(envelope):
            "Not found. (\(envelope.code))"
        case let .badRequest(envelope):
            "Request was rejected. (\(envelope.code))"
        case let .serverError(envelope):
            "Server error. (\(envelope.code))"
        case let .transport(error):
            "Network error: \(error.localizedDescription)"
        case let .decoding(error):
            "Response shape did not match. (\(error.localizedDescription))"
        case let .unexpectedStatus(code):
            "Unexpected HTTP status: \(code)."
        }
    }
}
