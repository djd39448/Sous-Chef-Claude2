//  FoodAttributes.swift
//
//  The open-map `attributes` JSONB sub-document on a Canonical Food Object —
//  a string-keyed bag of arbitrary JSON values.
//
//  Depends on:     Foundation.
//  Depended on by: FoodItem.attributes.
//  Why it exists:  the contract §4.2 declares `attributes` as a JSONB "open
//                  map" with no fixed schema — third-party payloads, ad-hoc
//                  AI annotations ("organic_preferred": true), etc. live
//                  here. dc-04 R1 calls JSONB-as-open-map an anti-pattern
//                  for anything you filter on; this column is read-back
//                  only, never queried, so the anti-pattern does not apply.
//                  Swift has no built-in `Any`-codable, so we model the
//                  values via a small JSONValue enum that round-trips the
//                  six JSON primitives. The decoder accepts any JSONB Postgres
//                  returns; the encoder emits the same shape on write.

import Foundation

/// JSONValue is the smallest tree that round-trips any JSON value. It is
/// purposefully nested here (not module-public) because no other type in
/// this milestone needs it; if a future Domain type also needs free-form
/// JSON, this gets promoted to its own file.
public indirect enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised JSON value at \(decoder.codingPath)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// FoodAttributes wraps the contract §4.2 JSONB `attributes` open map. It
/// defaults to empty per the SQL `DEFAULT '{}'::jsonb` clause; the wire
/// reflects that with `{}`.
public struct FoodAttributes: Codable, Sendable, Hashable {
    /// values holds the raw key/value bag. The dictionary is plain Swift —
    /// JSONB key uniqueness is enforced by Postgres on write.
    public let values: [String: JSONValue]

    public init(values: [String: JSONValue] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: JSONValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}
