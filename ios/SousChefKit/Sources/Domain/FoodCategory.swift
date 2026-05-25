//  FoodCategory.swift
//
//  The eight-value canonical food-category enum plus the optional secondary
//  subcategory string, mirroring the contract §4.2 JSONB `category` sub-
//  document.
//
//  Depends on:     Foundation.
//  Depended on by: FoodItem (one per row); the shopping-list category field
//                  (Phase E5 will use the same `Primary` enum to group items
//                  in the fixed display order).
//  Why it exists:  the contract enforces a closed set of nine primary values
//                  via a Postgres CHECK constraint (`contract/contract.md`
//                  §4.2). Mirroring it as a Swift `enum` makes the closed set
//                  load-bearing at the type level — a decode of an unknown
//                  string fails with a `DecodingError`, matching the data
//                  layer's behavior. The nested type lives next to the
//                  property it serializes so a reader sees the wire shape and
//                  the enum together (dc-00).

import Foundation

/// FoodCategory mirrors the contract §4.2 JSONB `category` sub-document.
/// The primary value is one of the contract's nine canonical categories;
/// the optional secondary string is a free-form refinement (e.g. "fresh
/// herbs" under produce). The snake_case wire keys are preserved verbatim
/// per contract §3.1 (JSONB sub-documents are not translated to camelCase).
public struct FoodCategory: Codable, Sendable, Hashable {
    /// Primary enumerates the nine canonical food categories. Order matches
    /// the contract's CHECK constraint (`contract/contract.md` §4.2). A
    /// decode of any other string fails — the contract guarantees the
    /// database never persists another value (`category_primary_known`).
    public enum Primary: String, Codable, Sendable, Hashable, CaseIterable {
        case produce
        case dairy
        case meat
        case seafood
        case pantry
        case frozen
        case bakery
        case beverages
        case other
    }

    /// primary is the canonical category. Always present.
    public let primary: Primary

    /// secondary is an optional free-form subcategory (e.g. "leafy greens").
    /// The contract marks it optional with the `?` suffix in §4.2.
    public let secondary: String?

    /// init lets call sites construct a FoodCategory directly — used by tests
    /// and by future write paths (Phase E onward).
    public init(primary: Primary, secondary: String? = nil) {
        self.primary = primary
        self.secondary = secondary
    }
}
