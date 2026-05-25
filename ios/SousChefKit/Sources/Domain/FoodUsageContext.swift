//  FoodUsageContext.swift
//
//  The `usage_context` JSONB sub-document on a Canonical Food Object —
//  the four-value role enum plus the optional cross-reference identifiers.
//
//  Depends on:     Foundation (UUID).
//  Depended on by: FoodItem.usageContext.
//  Why it exists:  contract §4.2 fixes the JSONB shape; ADR-0009 makes
//                  `usage_context.role` load-bearing — it is the column the
//                  inventory read path (contract §5.5 `GET /ingredients`)
//                  filters on. The four enum values are persisted in the
//                  `usage_context_role_known` CHECK constraint; the iOS
//                  decoder must match that enum exactly so an unknown role
//                  fails fast in tests, not silently rendered as "unknown"
//                  in the UI. Per ADR-0009, v1 code writes only `inventory`
//                  and `shopping`; `planned` and `ingredient` are reserved.

import Foundation

/// FoodUsageContext mirrors the contract §4.2 JSONB `usage_context` shape.
/// Optional fields use Swift's `Optional` and are omitted from the encoded
/// form when nil. All keys are snake_case per contract §3.1.
public struct FoodUsageContext: Codable, Sendable, Hashable {
    /// Role enumerates the four CFO roles per ADR-0009. The contract
    /// admits all four values via the database CHECK constraint; only
    /// `inventory` and `shopping` are written by v1 code. The decoder
    /// rejects any other string — that catches a contract drift in tests
    /// before the UI sees it.
    public enum Role: String, Codable, Sendable, Hashable, CaseIterable {
        case inventory
        case shopping
        case planned
        case ingredient
    }

    /// role is the CFO role this row plays. Required.
    public let role: Role

    /// required, when present, marks the item as a hard requirement of
    /// the recipe (vs. a nice-to-have). Optional per contract §4.2.
    public let required: Bool?

    /// recipeIds links the row to one or more `cookbook_recipes.id`
    /// values when the role is `ingredient`. Optional.
    public let recipeIds: [UUID]?

    /// mealPlanId links the row to a meal plan when the role is
    /// `planned`. Optional.
    public let mealPlanId: UUID?

    /// shoppingListId links the row to a shopping list when the role is
    /// `shopping`. Optional.
    public let shoppingListId: UUID?

    /// CodingKeys preserve the contract's snake_case JSONB keys.
    enum CodingKeys: String, CodingKey {
        case role
        case required
        case recipeIds = "recipe_ids"
        case mealPlanId = "meal_plan_id"
        case shoppingListId = "shopping_list_id"
    }

    public init(
        role: Role,
        required: Bool? = nil,
        recipeIds: [UUID]? = nil,
        mealPlanId: UUID? = nil,
        shoppingListId: UUID? = nil
    ) {
        self.role = role
        self.required = required
        self.recipeIds = recipeIds
        self.mealPlanId = mealPlanId
        self.shoppingListId = shoppingListId
    }
}
