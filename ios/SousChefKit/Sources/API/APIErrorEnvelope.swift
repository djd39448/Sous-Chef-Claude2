//  APIErrorEnvelope.swift
//
//  The contract §3.5 error envelope: `{ "error": "<code>", "details": <any>? }`.
//
//  Depends on:     Foundation; the Domain target's JSONValue (for the
//                  open-typed `details` payload).
//  Depended on by: APIError (the `serverError` case wraps an envelope) and
//                  APIClient (decodes the envelope from non-2xx responses).
//  Why it exists:  contract §3.5 is normative — every non-2xx JSON response
//                  uses this exact shape. Modelling it as its own type
//                  keeps the decode logic in one place and lets call sites
//                  branch on the `code` string against the normative error
//                  codes listed in §3.5 without re-implementing the parse.

import Domain
import Foundation

/// APIErrorEnvelope mirrors the contract §3.5 wire shape. The `error`
/// field is a snake_case identifier the client branches on; `details` is
/// an optional bag of structured context whose schema varies per error
/// code. The contract lists the normative codes; we keep the type
/// string-typed so a new code from the server does not crash the
/// envelope decode — the call site decides what to do with an unknown
/// code.
public struct APIErrorEnvelope: Codable, Sendable, Hashable {
    /// code is the snake_case identifier per contract §3.5.
    public let code: String

    /// details is the optional structured-context payload. It is decoded
    /// as a JSONValue so any contract-conforming shape round-trips
    /// without losing fidelity; the call site walks the tree when it
    /// needs a specific field (e.g. `unknown_field` → `details.field`).
    public let details: JSONValue?

    /// CodingKeys maps the wire's `error` JSON key onto the Swift
    /// `code` property — "error" is reserved enough in Swift code
    /// (every error type has an `error` somewhere) that renaming the
    /// stored property to `code` reads better at call sites.
    enum CodingKeys: String, CodingKey {
        case code = "error"
        case details
    }

    public init(code: String, details: JSONValue? = nil) {
        self.code = code
        self.details = details
    }
}
