//  FoodItem.swift
//
//  The Canonical Food Object — the single shape for inventory, shopping
//  items, planned ingredients, and recipe ingredients (contract §4.2,
//  behavior spec §2.1).
//
//  Depends on:     Foundation and every Food* sub-document type in this
//                  directory.
//  Depended on by: the API target's `ingredients()` method, the Plan tab's
//                  ingredients list, and (Phase E onward) the cookbook
//                  ingredient helper.
//  Why it exists:  this is the Swift mirror of the `food_items` table the
//                  data track owns (contract §4.2). Every wire field
//                  becomes a property at the precise contract type:
//                  UUID for ids, Date for timestamps, Decimal for amounts,
//                  enums for the closed sets. The decoder catches contract
//                  drift the moment a fixture stops round-tripping —
//                  rather than a silent UI render of garbage.
//
//                  Top-level wire keys are camelCase per contract §3.1
//                  (Go handlers translate the database snake_case column
//                  names at the wire boundary). The nested JSONB types
//                  keep their snake_case keys verbatim per the same
//                  paragraph.

import Foundation

/// FoodItem is the iOS-side mirror of the contract §4.2 `food_items` row.
/// The struct is `Identifiable` by `id` so SwiftUI ForEach can use it
/// directly, `Sendable` so it crosses actor boundaries (the APIClient
/// hands items to the main-actor view), and `Hashable` for cheap equality.
public struct FoodItem: Codable, Sendable, Hashable, Identifiable {
    /// id is the row's primary key — a UUIDv7 per contract §4.2.
    public let id: UUID

    /// userId is the owning Supabase user. The contract guarantees the
    /// caller only sees their own rows (RLS), so this is informational
    /// for the client.
    public let userId: UUID

    /// canonicalName is the lowercase singular generic form (e.g. "milk",
    /// "scallion"). The database enforces the lowercase invariant via a
    /// CHECK constraint; the iOS client trusts that and does not re-lower.
    public let canonicalName: String

    /// displayName is the human-readable form (e.g. "2% Milk", "Green
    /// Onions"). This is what the UI shows.
    public let displayName: String

    /// quantity is the optional amount-plus-unit pair. Null on rows the
    /// AI emitted without a measurement (e.g. "salt to taste").
    public let quantity: FoodQuantity?

    /// category is the 9-value primary category + optional secondary.
    public let category: FoodCategory

    /// attributes is the open JSONB map for ad-hoc annotations.
    public let attributes: FoodAttributes

    /// flexibility is the substitution-preferences sub-document.
    public let flexibility: FoodFlexibility

    /// usageContext carries the role enum (ADR-0009) and any cross-
    /// reference identifiers.
    public let usageContext: FoodUsageContext

    /// inventoryState carries the 4-value status enum plus the optional
    /// on-hand amount and last-confirmed timestamp.
    public let inventoryState: FoodInventoryState

    /// sourcing carries the store-affinity preferences.
    public let sourcing: FoodSourcing

    /// metadata carries the provenance enum and confidence score.
    public let metadata: FoodMetadata

    /// createdAt is the row's insertion time (RFC 3339 UTC on the wire,
    /// per contract §3.2).
    public let createdAt: Date

    /// updatedAt is the row's last modification time. The data track
    /// maintains it via a Postgres trigger.
    public let updatedAt: Date

    /// CodingKeys translates the wire's camelCase top-level field names
    /// to Swift's lowerCamelCase. The contract §3.1 says response bodies
    /// use camelCase except inside JSONB sub-documents, which keep their
    /// snake_case keys (handled by each nested type's own CodingKeys).
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case canonicalName
        case displayName
        case quantity
        case category
        case attributes
        case flexibility
        case usageContext
        case inventoryState
        case sourcing
        case metadata
        case createdAt
        case updatedAt
    }

    public init(
        id: UUID,
        userId: UUID,
        canonicalName: String,
        displayName: String,
        quantity: FoodQuantity?,
        category: FoodCategory,
        attributes: FoodAttributes,
        flexibility: FoodFlexibility,
        usageContext: FoodUsageContext,
        inventoryState: FoodInventoryState,
        sourcing: FoodSourcing,
        metadata: FoodMetadata,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.quantity = quantity
        self.category = category
        self.attributes = attributes
        self.flexibility = flexibility
        self.usageContext = usageContext
        self.inventoryState = inventoryState
        self.sourcing = sourcing
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
