//  CalendarTabView.swift
//
//  Placeholder for the Calendar tab — week and month drilldown views
//  (behavior spec §3.7).
//
//  Depends on:     SwiftUI and PlaceholderTabContent.
//  Depended on by: RootView's TabView.
//  Why it exists:  the gate review needs to see five tabs render. The real
//                  implementation lands in Week 2+ — task E4 of
//                  `track-ios.md` §5 (month grid with dots for weeks with
//                  plans, drill into a week or shopping list). This
//                  placeholder marks the slot without faking content.

import SwiftUI

struct CalendarTabView: View {
    /// summaryText spells out the Week-3 scope. Declared on its own line to
    /// keep the body under SwiftLint's 120-column limit.
    private let summaryText = """
    Month grid with dots for weeks that have plans or shopping lists; drills \
    into PlanRoute or ShoppingRoute.
    """

    var body: some View {
        NavigationStack {
            PlaceholderTabContent(
                tabTitle: "Calendar",
                upcomingMilestone: "Phase 4 Week 3",
                summary: summaryText
            )
            .navigationTitle("Calendar")
        }
    }
}

#Preview("Calendar tab placeholder") {
    CalendarTabView()
}
