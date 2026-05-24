//  ShoppingTabView.swift
//
//  Placeholder for the Shopping tab — shopping-list index and per-list detail
//  (behavior spec §3.8).
//
//  Depends on:     SwiftUI and PlaceholderTabContent.
//  Depended on by: RootView's TabView.
//  Why it exists:  the gate review needs to see five tabs render. The real
//                  implementation lands in Week 3+ — task E5 of
//                  `track-ios.md` §5 (category grouping in fixed order,
//                  per-item check toggle via `PATCH /shopping-items/{id}`,
//                  Clear Done scoped to the viewed list id per ADR-0007).
//                  This placeholder marks the slot without faking content.

import SwiftUI

struct ShoppingTabView: View {
    /// summaryText spells out the Week-3+ scope. It is declared on its own
    /// line so the body stays under SwiftLint's 120-column limit.
    private let summaryText = """
    Lists newest-first; per-list view groups items by category in the fixed \
    display order, with check toggle and Clear Done.
    """

    var body: some View {
        NavigationStack {
            PlaceholderTabContent(
                tabTitle: "Shopping",
                upcomingMilestone: "Phase 4 Week 3",
                summary: summaryText
            )
            .navigationTitle("Shopping")
        }
    }
}

#Preview("Shopping tab placeholder") {
    ShoppingTabView()
}
