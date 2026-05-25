//  FoodEnumDecodingTests.swift
//
//  Decoding invariants for each enum mirrored from contract §4.2: valid
//  wire literals decode; unknown literals fail.
//
//  Depends on:     the Domain library, Swift Testing.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  contract §4.2 enforces closed sets via Postgres CHECK
//                  constraints. The Swift enums mirror those sets exactly;
//                  this suite proves it. If a future contract addition
//                  introduces a new enum value, these tests fail until the
//                  enum is extended — that is the dc-00 alarm bell that
//                  catches contract drift before the UI silently swallows
//                  it as "other".

@testable import Domain
import Foundation
import Testing

@Suite("Food enum decoding")
struct FoodEnumDecodingTests {
    private func decode<T: Decodable>(_ json: String, as _: T.Type = T.self) throws -> T {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// categoryPrimaryAcceptsAllNineValues exercises every contract §4.2
    /// `category.primary` literal. The parameterized cases match the
    /// CHECK constraint in `category_primary_known`.
    @Test(
        "Every contract category.primary literal decodes to its enum case.",
        arguments: [
            ("produce", FoodCategory.Primary.produce),
            ("dairy", FoodCategory.Primary.dairy),
            ("meat", FoodCategory.Primary.meat),
            ("seafood", FoodCategory.Primary.seafood),
            ("pantry", FoodCategory.Primary.pantry),
            ("frozen", FoodCategory.Primary.frozen),
            ("bakery", FoodCategory.Primary.bakery),
            ("beverages", FoodCategory.Primary.beverages),
            ("other", FoodCategory.Primary.other),
        ]
    )
    func categoryPrimaryAcceptsAllNineValues(literal: String, expected: FoodCategory.Primary) throws {
        let category: FoodCategory = try decode("""
        { "primary": "\(literal)" }
        """)
        #expect(category.primary == expected)
    }

    /// categoryPrimaryRejectsUnknown verifies the closed-set guarantee.
    @Test("An unknown category.primary literal fails to decode.")
    func categoryPrimaryRejectsUnknown() {
        let json = """
        { "primary": "vegetabls" }
        """
        #expect(throws: DecodingError.self) {
            _ = try decode(json, as: FoodCategory.self)
        }
    }

    @Test(
        "Every contract usage_context.role literal decodes per ADR-0009.",
        arguments: [
            ("inventory", FoodUsageContext.Role.inventory),
            ("shopping", FoodUsageContext.Role.shopping),
            ("planned", FoodUsageContext.Role.planned),
            ("ingredient", FoodUsageContext.Role.ingredient),
        ]
    )
    func usageContextRoleAcceptsAllFourValues(literal: String, expected: FoodUsageContext.Role) throws {
        let context: FoodUsageContext = try decode("""
        { "role": "\(literal)" }
        """)
        #expect(context.role == expected)
    }

    @Test("A typo in usage_context.role fails to decode.")
    func usageContextRoleRejectsTypo() {
        let json = """
        { "role": "invntory" }
        """
        #expect(throws: DecodingError.self) {
            _ = try decode(json, as: FoodUsageContext.self)
        }
    }

    @Test(
        "Every contract inventory_state.status literal decodes.",
        arguments: [
            ("confirmed", FoodInventoryState.Status.confirmed),
            ("likely", FoodInventoryState.Status.likely),
            ("unknown", FoodInventoryState.Status.unknown),
            ("out", FoodInventoryState.Status.out),
        ]
    )
    func inventoryStatusAcceptsAllFourValues(literal: String, expected: FoodInventoryState.Status) throws {
        let state: FoodInventoryState = try decode("""
        { "status": "\(literal)", "on_hand_amount": null, "last_confirmed": null }
        """)
        #expect(state.status == expected)
    }

    @Test("An unknown inventory_state.status fails to decode.")
    func inventoryStatusRejectsUnknown() {
        let json = """
        { "status": "depleted", "on_hand_amount": null, "last_confirmed": null }
        """
        #expect(throws: DecodingError.self) {
            _ = try decode(json, as: FoodInventoryState.self)
        }
    }

    @Test(
        "Metadata created_by accepts only ai or user.",
        arguments: [
            ("ai", FoodMetadata.CreatedBy.ai),
            ("user", FoodMetadata.CreatedBy.user),
        ]
    )
    func metadataCreatedByAcceptsAllTwoValues(literal: String, expected: FoodMetadata.CreatedBy) throws {
        let meta: FoodMetadata = try decode("""
        { "created_by": "\(literal)", "confidence": 1.0 }
        """)
        #expect(meta.createdBy == expected)
    }

    @Test("Metadata created_by rejects anything else.")
    func metadataCreatedByRejectsUnknown() {
        let json = """
        { "created_by": "system", "confidence": 1.0 }
        """
        #expect(throws: DecodingError.self) {
            _ = try decode(json, as: FoodMetadata.self)
        }
    }
}
