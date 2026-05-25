//  FoodSourcing.swift
//
//  The `sourcing` JSONB sub-document — the user's preferences for how this
//  ingredient should be acquired (store affinity, bulk-ok, generic-ok).
//
//  Depends on:     Foundation.
//  Depended on by: FoodItem.sourcing.
//  Why it exists:  contract §4.2 fixes the JSONB shape with three keys.
//                  The shopping-list write path (contract §7.3) reads
//                  these preferences when grouping items by store. The
//                  iOS read paths surface them only in cookbook ingredient
//                  helpers (Phase E3); for Week 2 the type is decode-only.

import Foundation

/// FoodSourcing mirrors the contract §4.2 JSONB `sourcing` shape:
/// `{ "store_affinity": <string> | null, "bulk_allowed": <bool>,
/// "generic_ok": <bool> }`. Keys are snake_case verbatim per contract §3.1.
public struct FoodSourcing: Codable, Sendable, Hashable {
    /// storeAffinity is a free-form store name the user prefers ("Trader
    /// Joe's", "Costco"). Nullable when the user has no preference.
    public let storeAffinity: String?

    /// bulkAllowed signals whether buying in bulk is acceptable. Defaults
    /// to true in the Postgres column default.
    public let bulkAllowed: Bool

    /// genericOk signals whether a store-brand substitute is acceptable.
    /// Defaults to true.
    public let genericOk: Bool

    /// CodingKeys preserve the contract's snake_case JSONB keys.
    enum CodingKeys: String, CodingKey {
        case storeAffinity = "store_affinity"
        case bulkAllowed = "bulk_allowed"
        case genericOk = "generic_ok"
    }

    public init(
        storeAffinity: String? = nil,
        bulkAllowed: Bool = true,
        genericOk: Bool = true
    ) {
        self.storeAffinity = storeAffinity
        self.bulkAllowed = bulkAllowed
        self.genericOk = genericOk
    }
}
