//  FoodFlexibility.swift
//
//  The `flexibility` JSONB sub-document on a Canonical Food Object —
//  whether the user accepts substitutions and which ones.
//
//  Depends on:     Foundation.
//  Depended on by: FoodItem.flexibility.
//  Why it exists:  contract §4.2 fixes the JSONB shape with three keys;
//                  modelling it as a struct keeps decoding strict (an
//                  unexpected nested key would silently round-trip with
//                  JSONValue but a typed struct surfaces it during testing
//                  if the contract drifts). The defaults
//                  (`substitution_allowed: true`, `strict: false`,
//                  `acceptable_variants: []`) are the Postgres column
//                  default per §4.2; the wire always materialises them.

import Foundation

/// FoodFlexibility mirrors the contract §4.2 JSONB `flexibility` shape:
/// `{ "substitution_allowed": <bool>, "acceptable_variants": <string[]>,
/// "strict": <bool> }`. Keys are snake_case verbatim per contract §3.1.
public struct FoodFlexibility: Codable, Sendable, Hashable {
    /// substitutionAllowed signals whether the user accepts a generic
    /// substitute (e.g. "any green onion" for "scallions"). Defaults to
    /// true in the Postgres column default; the AI may set it to false.
    public let substitutionAllowed: Bool

    /// acceptableVariants is a free-form list of substitute strings the
    /// user has approved.
    public let acceptableVariants: [String]

    /// strict signals whether the AI must use this exact item (no
    /// substitution even from acceptableVariants).
    public let strict: Bool

    /// CodingKeys preserves the contract's snake_case JSONB keys.
    enum CodingKeys: String, CodingKey {
        case substitutionAllowed = "substitution_allowed"
        case acceptableVariants = "acceptable_variants"
        case strict
    }

    public init(
        substitutionAllowed: Bool = true,
        acceptableVariants: [String] = [],
        strict: Bool = false
    ) {
        self.substitutionAllowed = substitutionAllowed
        self.acceptableVariants = acceptableVariants
        self.strict = strict
    }
}
