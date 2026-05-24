//  PlanTabView.swift
//
//  Placeholder for the Plan tab — the weekly meal-plan surface
//  (behavior spec §3.3).
//
//  Depends on:     SwiftUI and PlaceholderTabContent.
//  Depended on by: RootView's TabView.
//  Why it exists:  the gate review needs to see five tabs render. The real
//                  implementation lands in Week 2+ — tasks D1–D4 of
//                  `track-ios.md` §5 (week navigator, seven MealPlanCards in
//                  Mon→Sun UI order, edit-mode + selective regeneration,
//                  recipe detail with SSE generation). This placeholder marks
//                  the slot without faking content.

import SwiftUI

struct PlanTabView: View {
    /// summaryText spells out the Week-2 scope. Declared on its own line to
    /// keep the body under SwiftLint's 120-column limit.
    private let summaryText = """
    Sticky week navigator, seven meal-plan cards Mon→Sun, edit-mode with \
    selective day regeneration.
    """

    var body: some View {
        NavigationStack {
            PlaceholderTabContent(
                tabTitle: "Plan",
                upcomingMilestone: "Phase 4 Week 2",
                summary: summaryText
            )
            .navigationTitle("Plan")
        }
    }
}

#Preview("Plan tab placeholder") {
    PlanTabView()
}
