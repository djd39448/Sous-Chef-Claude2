//  FoodInventoryState.swift
//
//  The `inventory_state` JSONB sub-document — the four-value status enum
//  plus the optional on-hand amount and last-confirmed timestamp.
//
//  Depends on:     Foundation (Date).
//  Depended on by: FoodItem.inventoryState.
//  Why it exists:  contract §4.2 fixes the JSONB shape and the database
//                  CHECK constraint (`inventory_state_status_known`) pins
//                  the four valid status strings. The `GET /ingredients`
//                  read path (contract §5.5) filters out rows where
//                  `inventory_state.status = "out"`, so the iOS UI never
//                  sees a stocked-out row in the inventory list — but it
//                  must still decode them safely if the contract changes
//                  later. The decoder rejects any other status; the UI is
//                  guaranteed a closed set.

import Foundation

/// FoodInventoryState mirrors the contract §4.2 JSONB `inventory_state`
/// shape: `{ "status": <enum>, "on_hand_amount": <number> | null,
/// "last_confirmed": <RFC3339> | null }`. Keys are snake_case verbatim per
/// contract §3.1.
public struct FoodInventoryState: Codable, Sendable, Hashable {
    /// Status enumerates the four inventory states. The contract's
    /// `update_ingredients` tool admits three of them (`confirmed`,
    /// `likely`, `out` per §7.1) on write; the fourth (`unknown`) is the
    /// Postgres column default for rows seeded without an explicit
    /// status (§4.2). The iOS decoder admits all four.
    public enum Status: String, Codable, Sendable, Hashable, CaseIterable {
        case confirmed
        case likely
        case unknown
        case out
    }

    /// status is the current inventory state. Required.
    public let status: Status

    /// onHandAmount is the rough quantity the user reports on hand. The
    /// contract leaves it nullable (the AI may not know it) so this is
    /// an Optional Decimal. Decimal so user-typed numbers round-trip
    /// exactly.
    public let onHandAmount: Decimal?

    /// lastConfirmed is the RFC 3339 timestamp the inventory state was
    /// last verified (e.g. via an `update_ingredients` tool call). The
    /// contract leaves it nullable.
    public let lastConfirmed: Date?

    /// CodingKeys preserve the contract's snake_case JSONB keys.
    enum CodingKeys: String, CodingKey {
        case status
        case onHandAmount = "on_hand_amount"
        case lastConfirmed = "last_confirmed"
    }

    public init(
        status: Status = .unknown,
        onHandAmount: Decimal? = nil,
        lastConfirmed: Date? = nil
    ) {
        self.status = status
        self.onHandAmount = onHandAmount
        self.lastConfirmed = lastConfirmed
    }
}
