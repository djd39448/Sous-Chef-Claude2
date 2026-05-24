//  CookbookTabView.swift
//
//  Placeholder for the Cookbook tab — saved-recipe index and detail
//  (behavior spec §3.5, §3.6).
//
//  Depends on:     SwiftUI and PlaceholderTabContent.
//  Depended on by: RootView's TabView.
//  Why it exists:  the gate review needs to see five tabs render. The real
//                  implementation lands in Week 3+ — tasks E2/E3 of
//                  `track-ios.md` §5 (cookbook list with thumbnails, edit
//                  mode with the ingredient-helper widget, regenerate-image
//                  affordance backed by the 128 MB on-device LRU cache from
//                  ADR-0004). This placeholder marks the slot without faking
//                  content.

import SwiftUI

struct CookbookTabView: View {
    /// summaryText spells out the Week-3 scope. Declared on its own line to
    /// keep the body under SwiftLint's 120-column limit.
    private let summaryText = """
    Saved recipes newest-first with cached thumbnails, edit mode with \
    ingredient helper, explicit regenerate-image affordance.
    """

    var body: some View {
        NavigationStack {
            PlaceholderTabContent(
                tabTitle: "Cookbook",
                upcomingMilestone: "Phase 4 Week 3",
                summary: summaryText
            )
            .navigationTitle("Cookbook")
        }
    }
}

#Preview("Cookbook tab placeholder") {
    CookbookTabView()
}
