//  FoodItemCodableTests.swift
//
//  Round-trip decode + encode tests for FoodItem and every nested JSONB
//  sub-document type.
//
//  Depends on:     the Domain library, Swift Testing, FoodItemFixture.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  dc-07 says new logic ships with tests. The contract §4.2
//                  wire shape is the load-bearing artifact this whole
//                  Domain target encodes; if the decoder ever stops
//                  matching the contract, this test fails before the UI
//                  sees a malformed row. The fixture is shared with
//                  FoodEnumDecodingTests, but the round-trip assertion
//                  lives here so a reader sees decode -> re-encode ->
//                  decode-again in one place (`#expect(roundTripped ==
//                  original)`).

@testable import Domain
import Foundation
import Testing

@Suite("FoodItem Codable round-trip")
struct FoodItemCodableTests {
    /// makeDecoder returns the decoder configured the way `APIClient` will
    /// configure its production decoder — ISO 8601 timestamps with a `Z`
    /// suffix per contract §3.2. The tests assert against the same
    /// configuration the production code uses so passing here means
    /// passing in the app.
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// makeEncoder mirrors makeDecoder — ISO 8601 output so the round-trip
    /// is byte-comparable.
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    @Test("Canonical fixture decodes every field correctly.")
    func decodesCanonicalFixture() throws {
        let decoder = makeDecoder()
        let item = try decoder.decode(FoodItem.self, from: FoodItemFixture.canonicalJSONData)

        #expect(item.id == UUID(uuidString: "01923456-7890-7abc-8def-0123456789ab"))
        #expect(item.userId == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        #expect(item.canonicalName == "scallion")
        #expect(item.displayName == "Green Onions")
        #expect(item.quantity?.amount == Decimal(string: "1.5"))
        #expect(item.quantity?.unit == "bunch")
        #expect(item.category.primary == .produce)
        #expect(item.category.secondary == "fresh herbs")
        #expect(item.flexibility.substitutionAllowed == true)
        #expect(item.flexibility.acceptableVariants == ["green onion", "spring onion"])
        #expect(item.flexibility.strict == false)
        #expect(item.usageContext.role == .inventory)
        #expect(item.usageContext.required == true)
        let recipeID = try #require(UUID(uuidString: "aaaa1111-2222-3333-4444-555555555555"))
        #expect(item.usageContext.recipeIds == [recipeID])
        #expect(item.usageContext.mealPlanId == UUID(uuidString: "bbbb1111-2222-3333-4444-555555555555"))
        #expect(item.usageContext.shoppingListId == UUID(uuidString: "cccc1111-2222-3333-4444-555555555555"))
        #expect(item.inventoryState.status == .confirmed)
        #expect(item.inventoryState.onHandAmount == Decimal(2))
        #expect(item.inventoryState.lastConfirmed != nil)
        #expect(item.sourcing.storeAffinity == "Trader Joe's")
        #expect(item.sourcing.bulkAllowed == false)
        #expect(item.sourcing.genericOk == true)
        #expect(item.metadata.createdBy == .ai)
        #expect(item.metadata.confidence == Decimal(string: "0.95"))
    }

    @Test("Decoded item re-encodes and decodes back to an equal value.")
    func roundTrips() throws {
        let decoder = makeDecoder()
        let encoder = makeEncoder()
        let original = try decoder.decode(FoodItem.self, from: FoodItemFixture.canonicalJSONData)
        let reEncoded = try encoder.encode(original)
        let roundTripped = try decoder.decode(FoodItem.self, from: reEncoded)
        #expect(roundTripped == original)
    }

    @Test("Attributes preserves arbitrary JSONB content through a round trip.")
    func attributesPreserveArbitraryJSON() throws {
        let decoder = makeDecoder()
        let encoder = makeEncoder()
        let item = try decoder.decode(FoodItem.self, from: FoodItemFixture.canonicalJSONData)
        // The fixture's attributes hold one bool and one string. Both must
        // survive the encode/decode cycle since attributes is the open-map.
        #expect(item.attributes.values["organic_preferred"] == .bool(true))
        #expect(item.attributes.values["notes"] == .string("from farmers market"))
        let reEncoded = try encoder.encode(item.attributes)
        let again = try decoder.decode(FoodAttributes.self, from: reEncoded)
        #expect(again == item.attributes)
    }

    @Test("A FoodItem with a null quantity decodes the optional as nil.")
    func nullQuantityDecodesAsNil() throws {
        let json = """
        {
          "id": "01923456-7890-7abc-8def-0123456789ab",
          "userId": "11111111-2222-3333-4444-555555555555",
          "canonicalName": "salt",
          "displayName": "Salt",
          "quantity": null,
          "category": { "primary": "pantry" },
          "attributes": {},
          "flexibility": {
            "substitution_allowed": true,
            "acceptable_variants": [],
            "strict": false
          },
          "usageContext": { "role": "inventory" },
          "inventoryState": {
            "status": "unknown",
            "on_hand_amount": null,
            "last_confirmed": null
          },
          "sourcing": {
            "store_affinity": null,
            "bulk_allowed": true,
            "generic_ok": true
          },
          "metadata": { "created_by": "user", "confidence": 1.0 },
          "createdAt": "2026-05-20T10:00:00Z",
          "updatedAt": "2026-05-20T10:00:00Z"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = makeDecoder()
        let item = try decoder.decode(FoodItem.self, from: data)
        #expect(item.quantity == nil)
        #expect(item.category.secondary == nil)
        #expect(item.inventoryState.onHandAmount == nil)
        #expect(item.inventoryState.lastConfirmed == nil)
        #expect(item.sourcing.storeAffinity == nil)
    }
}
