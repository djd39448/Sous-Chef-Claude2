//  Domain.swift
//
//  The Domain library — entities, value types, and pure business logic for the
//  sous-chef-ios app.
//
//  Depends on:     Foundation only. Never SwiftUI, never URLSession, never any
//                  third-party SDK. This is the testable core.
//  Depended on by: the API target (DTOs convert into Domain types), the Auth
//                  target (identity values), and the SousChef app target
//                  (every screen consumes Domain models). Markdown and
//                  ImageCache are independent of Domain.
//  Why it exists:  per `track-ios.md` §3.1 and dc-03, model types must not
//                  link SwiftUI. Hosting them in a SwiftPM target that does
//                  not depend on SwiftUI makes the rule a compile-time
//                  guarantee. This file is intentionally minimal in Week 1 —
//                  Week 2 (task B1 of `track-ios.md` §5) populates it with
//                  Conversation, MealPlan, CookbookRecipe, ShoppingList,
//                  FoodItem, and the `WeekDate` value type that enforces
//                  Monday-of-week per ADR-0010 (`contract/contract.md` §3.2).

import Foundation

/// SousChefDomainVersion is a build-time identifier the app target can read to
/// confirm that the Domain library compiled and linked correctly. It will be
/// removed once real Domain types land in Week 2.
public enum SousChefDomainVersion {
    /// current is the marker string the app prints at first launch. The value
    /// is meaningful only as evidence the package is wired in.
    public static let current = "0.1.0-foundation"
}
