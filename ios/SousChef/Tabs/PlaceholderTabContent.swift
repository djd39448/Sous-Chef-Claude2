//  PlaceholderTabContent.swift
//
//  The shared placeholder body each of the five tab views renders in Week 1.
//
//  Depends on:     SwiftUI.
//  Depended on by: ChatTabView, PlanTabView, CalendarTabView,
//                  CookbookTabView, ShoppingTabView.
//  Why it exists:  every tab needs to render something in Week 1 so the gate
//                  review can confirm the navigation skeleton works.
//                  Centralizing the placeholder keeps the five tab files
//                  short and consistent: each names its tab, its upcoming
//                  Phase 4 milestone, and a one-line description of the real
//                  implementation that lands later. Per dc-00, a reader
//                  opens any of these and immediately sees what is missing
//                  and when it lands.

import SwiftUI

struct PlaceholderTabContent: View {
    /// tabTitle is the human-readable tab name shown at the top.
    let tabTitle: String

    /// upcomingMilestone is the Phase 4 week label when this tab's real
    /// implementation lands — for example "Phase 4 Week 2". The label is
    /// rendered prominently so reviewers see scope at a glance.
    let upcomingMilestone: String

    /// summary is a one-sentence description of what the tab will contain
    /// once implemented. Sourced from `track-ios.md` §3 / behavior spec §3.
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tabTitle)
                .font(.largeTitle)
                .bold()
            Text("Placeholder — lands in \(upcomingMilestone).")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.body)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tabTitle) tab. Placeholder. Lands in \(upcomingMilestone). \(summary)")
    }
}

#Preview("Placeholder content") {
    PlaceholderTabContent(
        tabTitle: "Chat",
        upcomingMilestone: "Phase 4 Week 2",
        summary: "Multi-conversation chat with the kitchen sous-chef."
    )
}
