//  RootView.swift
//
//  The top-level signed-in scene — a five-tab TabView matching the gate
//  decision in `track-ios.md` §3.2.
//
//  Depends on:     SwiftUI and the five placeholder tab views (ChatTabView,
//                  PlanTabView, CalendarTabView, CookbookTabView,
//                  ShoppingTabView) that share this file's directory.
//  Depended on by: SousChefApp when the user is signed in.
//  Why it exists:  every per-tab NavigationStack root and the typed
//                  NavigationPath plumbing (ADR-0005) hangs off this shell.
//                  In Week 1 the shell exists so the gate can see the
//                  navigation skeleton; the tabs themselves are placeholders.
//                  Real tab content lands in Weeks 2+ per `track-ios.md` §5.

import SwiftUI

/// RootTab enumerates the five tabs in the order the user sees them. The raw
/// values match the Conductor's gate decision: Chat, Plan, Calendar,
/// Cookbook, Shopping. The enum is `Hashable` so a future @SceneStorage line
/// (task F1 of `track-ios.md` §5) can persist the last-selected tab.
enum RootTab: String, Hashable, CaseIterable {
    case chat
    case plan
    case calendar
    case cookbook
    case shopping

    /// title is the human-readable tab label rendered on the bar.
    var title: String {
        switch self {
        case .chat: "Chat"
        case .plan: "Plan"
        case .calendar: "Calendar"
        case .cookbook: "Cookbook"
        case .shopping: "Shopping"
        }
    }

    /// systemImage is the SF Symbol shown above the title. These are
    /// provisional — visual polish is task F2 of `track-ios.md` §5.
    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .plan: "calendar.day.timeline.left"
        case .calendar: "calendar"
        case .cookbook: "book.closed"
        case .shopping: "cart"
        }
    }
}

struct RootView: View {
    /// selection is local view state; persistence across launches lands with
    /// task F1 of `track-ios.md` §5.
    @State private var selection: RootTab = .chat

    var body: some View {
        TabView(selection: $selection) {
            ChatTabView()
                .tabItem { Label(RootTab.chat.title, systemImage: RootTab.chat.systemImage) }
                .tag(RootTab.chat)
            PlanTabView()
                .tabItem { Label(RootTab.plan.title, systemImage: RootTab.plan.systemImage) }
                .tag(RootTab.plan)
            CalendarTabView()
                .tabItem { Label(RootTab.calendar.title, systemImage: RootTab.calendar.systemImage) }
                .tag(RootTab.calendar)
            CookbookTabView()
                .tabItem { Label(RootTab.cookbook.title, systemImage: RootTab.cookbook.systemImage) }
                .tag(RootTab.cookbook)
            ShoppingTabView()
                .tabItem { Label(RootTab.shopping.title, systemImage: RootTab.shopping.systemImage) }
                .tag(RootTab.shopping)
        }
    }
}

#Preview("Root tab shell") {
    RootView()
}
