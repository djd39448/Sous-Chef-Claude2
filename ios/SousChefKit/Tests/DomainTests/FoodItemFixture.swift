//  FoodItemFixture.swift
//
//  Canonical contract-§4.2-shaped JSON fixtures used by Domain decode/encode
//  tests.
//
//  Depends on:     Foundation only (the fixtures are raw byte arrays).
//  Depended on by: FoodItemCodableTests and FoodEnumDecodingTests. No
//                  production code links these helpers — they live in the
//                  test target.
//  Why it exists:  the contract fixes the wire shape; the fixture is the
//                  single canonical example every Domain decode test uses.
//                  Keeping the JSON literals in one file (rather than
//                  inline-spread across the test cases) means a contract
//                  change touches one place. The fixture also documents the
//                  shape — a reader of these tests sees exactly what the
//                  server emits per `contract/contract.md` §4.2.

import Foundation

/// FoodItemFixture holds canonical wire-shaped JSON for `food_items` rows
/// returned by `GET /api/kitchen/ingredients`. All fields are populated so
/// every decode path is exercised (no Optional left untouched).
enum FoodItemFixture {
    /// canonicalJSON is the wire shape per contract §4.2: top-level fields
    /// in camelCase (per §3.1 the Go handlers translate column names),
    /// nested JSONB sub-documents in snake_case verbatim (per §3.1 the
    /// JSONB shapes round-trip unmodified). Every nullable field is
    /// present and non-null so the round-trip test verifies real values
    /// survive both directions.
    static let canonicalJSON: String = #"""
    {
      "id": "01923456-7890-7abc-8def-0123456789ab",
      "userId": "11111111-2222-3333-4444-555555555555",
      "canonicalName": "scallion",
      "displayName": "Green Onions",
      "quantity": { "amount": 1.5, "unit": "bunch" },
      "category": { "primary": "produce", "secondary": "fresh herbs" },
      "attributes": { "organic_preferred": true, "notes": "from farmers market" },
      "flexibility": {
        "substitution_allowed": true,
        "acceptable_variants": ["green onion", "spring onion"],
        "strict": false
      },
      "usageContext": {
        "role": "inventory",
        "required": true,
        "recipe_ids": ["aaaa1111-2222-3333-4444-555555555555"],
        "meal_plan_id": "bbbb1111-2222-3333-4444-555555555555",
        "shopping_list_id": "cccc1111-2222-3333-4444-555555555555"
      },
      "inventoryState": {
        "status": "confirmed",
        "on_hand_amount": 2,
        "last_confirmed": "2026-05-24T18:42:11Z"
      },
      "sourcing": {
        "store_affinity": "Trader Joe's",
        "bulk_allowed": false,
        "generic_ok": true
      },
      "metadata": { "created_by": "ai", "confidence": 0.95 },
      "createdAt": "2026-05-20T10:00:00Z",
      "updatedAt": "2026-05-24T18:42:11Z"
    }
    """#

    /// canonicalJSONData is the same content as `canonicalJSON` but
    /// pre-encoded to UTF-8 bytes so test cases call `JSONDecoder` without
    /// repeating the conversion.
    static var canonicalJSONData: Data {
        guard let data = canonicalJSON.data(using: .utf8) else {
            // The literal above is ASCII; a UTF-8 conversion failure here is
            // a Swift-runtime bug, not a contract change.
            fatalError("FoodItemFixture.canonicalJSON failed to encode as UTF-8.")
        }
        return data
    }
}
