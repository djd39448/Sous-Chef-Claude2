//  FoodMetadata.swift
//
//  The `metadata` JSONB sub-document — provenance and confidence of a CFO
//  row.
//
//  Depends on:     Foundation.
//  Depended on by: FoodItem.metadata.
//  Why it exists:  contract §4.2 fixes the JSONB shape with two keys and a
//                  CHECK constraint (`metadata_created_by_known`) on the
//                  `created_by` enum. Confidence is a 0..1 number the AI
//                  emits when status is `likely` (per contract §7.1).
//                  Decimal preserves the AI's reported precision; clients
//                  display it as a percentage rounded to the nearest tenth.

import Foundation

/// FoodMetadata mirrors the contract §4.2 JSONB `metadata` shape:
/// `{ "created_by": "ai" | "user", "confidence": <number 0..1> }`. Keys
/// are snake_case verbatim per contract §3.1.
public struct FoodMetadata: Codable, Sendable, Hashable {
    /// CreatedBy is the two-value provenance enum. The database CHECK
    /// constraint (`metadata_created_by_known`) bounds the column to
    /// these two strings; the decoder rejects anything else. The `ai`
    /// case is a contract literal (`contract/contract.md` §4.2,
    /// `metadata_created_by_known`) — its short identifier matches the
    /// wire value verbatim, hence the SwiftLint suppression.
    public enum CreatedBy: String, Codable, Sendable, Hashable, CaseIterable {
        // swiftlint:disable:next identifier_name
        case ai
        case user
    }

    /// createdBy is the row's provenance. Required.
    public let createdBy: CreatedBy

    /// confidence is a 0..1 score the AI emits with each write. The
    /// contract pins the range; the iOS code does not re-validate the
    /// range on decode (a faithful contract violation surfaces in tests).
    public let confidence: Decimal

    /// CodingKeys preserve the contract's snake_case JSONB keys.
    enum CodingKeys: String, CodingKey {
        case createdBy = "created_by"
        case confidence
    }

    public init(createdBy: CreatedBy, confidence: Decimal) {
        self.createdBy = createdBy
        self.confidence = confidence
    }
}
