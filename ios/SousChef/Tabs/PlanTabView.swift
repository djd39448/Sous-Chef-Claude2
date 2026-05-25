//  PlanTabView.swift
//
//  The Plan tab root — in Week 2 it renders the real ingredients list
//  via APIClient.ingredients(). The full weekly-meal-plan surface
//  (sticky week navigator, seven MealPlanCards, edit-mode + selective
//  regeneration) lands in tasks D2–D4 of `track-ios.md` §5.
//
//  Depends on:     SwiftUI; SousChefKit's API library (APIClient); the
//                  Plan feature's IngredientsModel + IngredientsListView.
//  Depended on by: RootView's TabView.
//  Why it exists:  the iOS track plan §5 D1 task lands the Plan tab's
//                  read path against the live backend. The full meal-
//                  plan UI is a multi-week build; the ingredients list
//                  is the first end-to-end vertical slice and proves the
//                  Domain + API libraries thread cleanly through the
//                  app target. Week 2's auth-token provider returns a
//                  placeholder ("dev-token"); the backend rejects it
//                  with 401, which the view renders as a "Sign in to
//                  load" state per the work-prompt's specified end-to-
//                  end behavior. Week 3 swaps the placeholder for the
//                  real AuthModel JWT.

import API
import Foundation
import SwiftUI

/// PlanDevConstants centralises the temporary scaffolding values the
/// Week-2 build uses while AuthModel is unfinished. Each constant has
/// a follow-up week pinned next to it so a reader knows when it
/// disappears.
enum PlanDevConstants {
    /// devBaseURL is the local-dev backend host per the iOS track plan
    /// §9 open question 2. Phase F3 swaps this for the per-build-
    /// configuration host once TestFlight wiring lands.
    static let devBaseURL: URL = {
        guard let url = URL(string: "http://127.0.0.1:8080") else {
            // The literal is hardcoded; a parse failure is a Foundation
            // runtime bug, not a contract change.
            fatalError("PlanDevConstants.devBaseURL: malformed URL literal.")
        }
        return url
    }()

    /// devToken is the placeholder bearer the dev build attaches per
    /// the work-prompt: "the backend will reject this with 401, which
    /// is the correct end-to-end behavior to render." Replaced by
    /// AuthModel.currentSession?.accessToken in Week 3.
    static let devToken = "dev-token"
}

struct PlanTabView: View {
    /// model is the @Observable that owns the ingredients load state.
    /// Held as @State because PlanTabView is the creator (dc-03: "a
    /// view that creates an @Observable object holds it with @State").
    @State private var model = IngredientsModel(
        client: APIClient(
            baseURL: PlanDevConstants.devBaseURL,
            authTokenProvider: { PlanDevConstants.devToken }
        )
    )

    var body: some View {
        NavigationStack {
            IngredientsListView(model: model)
        }
    }
}

#Preview("Plan tab — idle (no network)") {
    PlanTabView()
}
