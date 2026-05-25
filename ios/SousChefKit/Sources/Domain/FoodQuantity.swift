//  FoodQuantity.swift
//
//  The optional quantity sub-document for a Canonical Food Object — an
//  amount paired with a free-form unit string.
//
//  Depends on:     Foundation (Decimal).
//  Depended on by: FoodItem.quantity (nullable per contract §4.2). The
//                  shopping-list write path (Phase E5) reuses this shape
//                  before flattening to the "{amount} {unit}" string the
//                  `shopping_list_items.quantity` column stores.
//  Why it exists:  the contract §4.2 JSONB shape pins exactly two fields
//                  (`amount` and `unit`). Modelling it as its own type keeps
//                  the FoodItem struct readable and gives the unit tests a
//                  small focused subject. Decimal is chosen over Double so a
//                  3.0 amount round-trips as `3.0` not `2.9999…`; recipe
//                  quantities are user-readable values, not floats.

import Foundation

/// FoodQuantity mirrors the contract §4.2 JSONB `quantity` sub-document.
/// The wire shape is `{ "amount": <number>, "unit": <string> } | null`;
/// the null case is represented by storing the whole `FoodQuantity` as
/// `nil` on the parent (FoodItem.quantity is optional).
public struct FoodQuantity: Codable, Sendable, Hashable {
    /// amount is the numeric quantity. Stored as Decimal so user-typed
    /// fractions ("1.5 cups") round-trip exactly. Per contract §4.2 the
    /// wire type is `<number>` — JSONDecoder decodes that into Decimal
    /// when the destination type is Decimal.
    public let amount: Decimal

    /// unit is the free-form unit string ("cup", "tbsp", "lb", "ea"). The
    /// contract does not constrain its vocabulary; the AI emits whatever
    /// reads naturally to the user.
    public let unit: String

    /// init lets test fixtures and future write paths construct quantities
    /// directly. Initializers stay public so the type is usable across
    /// module boundaries.
    public init(amount: Decimal, unit: String) {
        self.amount = amount
        self.unit = unit
    }
}
