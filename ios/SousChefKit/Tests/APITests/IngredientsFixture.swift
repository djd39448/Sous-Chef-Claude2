//  IngredientsFixture.swift
//
//  Canonical wire-shaped JSON for the `GET /api/kitchen/ingredients`
//  response — the contract §5.5 envelope wrapping an array of FoodItem.
//
//  Depends on:     Foundation.
//  Depended on by: APIClientIngredientsTests; possibly future API tests
//                  for the same endpoint.
//  Why it exists:  the API test target needs an independent fixture so
//                  changes to the Domain fixture don't silently break
//                  API tests (or vice versa). The shape is duplicated
//                  deliberately — both fixtures must round-trip per the
//                  contract; the redundancy is the gate that catches a
//                  contract drift at either level.

import Foundation

/// IngredientsFixture holds canned `GET /ingredients` envelopes.
enum IngredientsFixture {
    /// twoItemsJSON is a two-element ingredients response. The first
    /// row matches the FoodItem canonical fixture from Domain tests;
    /// the second exercises the null-quantity / minimal-shape path
    /// that the Domain `nullQuantityDecodesAsNil` test also exercises,
    /// proving the array case threads both shapes through the
    /// decoder without losing precision.
    static let twoItemsJSON: String = #"""
    {
      "ingredients": [
        {
          "id": "01923456-7890-7abc-8def-0123456789ab",
          "userId": "11111111-2222-3333-4444-555555555555",
          "canonicalName": "scallion",
          "displayName": "Green Onions",
          "quantity": { "amount": 1.5, "unit": "bunch" },
          "category": { "primary": "produce", "secondary": "fresh herbs" },
          "attributes": {},
          "flexibility": {
            "substitution_allowed": true,
            "acceptable_variants": ["green onion"],
            "strict": false
          },
          "usageContext": { "role": "inventory" },
          "inventoryState": {
            "status": "confirmed",
            "on_hand_amount": 2,
            "last_confirmed": "2026-05-24T18:42:11Z"
          },
          "sourcing": {
            "store_affinity": null,
            "bulk_allowed": true,
            "generic_ok": true
          },
          "metadata": { "created_by": "ai", "confidence": 0.95 },
          "createdAt": "2026-05-20T10:00:00Z",
          "updatedAt": "2026-05-24T18:42:11Z"
        },
        {
          "id": "02923456-7890-7abc-8def-0123456789ab",
          "userId": "11111111-2222-3333-4444-555555555555",
          "canonicalName": "salt",
          "displayName": "Sea Salt",
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
            "status": "likely",
            "on_hand_amount": null,
            "last_confirmed": null
          },
          "sourcing": {
            "store_affinity": null,
            "bulk_allowed": true,
            "generic_ok": true
          },
          "metadata": { "created_by": "user", "confidence": 1.0 },
          "createdAt": "2026-05-19T08:30:00Z",
          "updatedAt": "2026-05-19T08:30:00Z"
        }
      ]
    }
    """#

    /// twoItemsJSONData is the canned JSON pre-encoded to UTF-8 bytes.
    static var twoItemsJSONData: Data {
        guard let data = twoItemsJSON.data(using: .utf8) else {
            fatalError("IngredientsFixture.twoItemsJSON failed to encode as UTF-8.")
        }
        return data
    }

    /// emptyJSONData is the response for a user with no inventory rows.
    /// The contract guarantees an empty array, not a missing field.
    static var emptyJSONData: Data {
        let json = #"{ "ingredients": [] }"#
        guard let data = json.data(using: .utf8) else {
            fatalError("IngredientsFixture.empty failed to encode as UTF-8.")
        }
        return data
    }

    /// errorEnvelopeJSON returns the contract §3.5 error shape for a
    /// given code. Used by the error-mapping tests.
    static func errorEnvelopeJSONData(code: String) -> Data {
        let json = #"{ "error": "\#(code)" }"#
        guard let data = json.data(using: .utf8) else {
            fatalError("errorEnvelopeJSONData failed to encode as UTF-8.")
        }
        return data
    }
}
