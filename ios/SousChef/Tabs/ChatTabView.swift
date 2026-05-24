//  ChatTabView.swift
//
//  Placeholder for the Chat tab — multi-conversation chat with the kitchen
//  sous-chef (behavior spec §3.2).
//
//  Depends on:     SwiftUI and PlaceholderTabContent.
//  Depended on by: RootView's TabView.
//  Why it exists:  the gate review needs to see five tabs render. The real
//                  implementation lands in Week 2+ — task C1/C2/C3 of
//                  `track-ios.md` §5 (conversation sidebar, SSE-streamed
//                  assistant messages, fresh-chat-on-session-start). This
//                  placeholder marks the slot without faking content.

import SwiftUI

struct ChatTabView: View {
    /// summaryText spells out the Week-2 scope. Declared on its own line to
    /// keep the body under SwiftLint's 120-column limit.
    private let summaryText = """
    Multi-conversation chat with the kitchen sous-chef. SSE-streamed \
    assistant replies, suggestion chips, sidebar grouped by recency.
    """

    var body: some View {
        NavigationStack {
            PlaceholderTabContent(
                tabTitle: "Chat",
                upcomingMilestone: "Phase 4 Week 2",
                summary: summaryText
            )
            .navigationTitle("Chat")
        }
    }
}

#Preview("Chat tab placeholder") {
    ChatTabView()
}
