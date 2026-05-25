//  IngredientsListView.swift
//
//  The Plan-tab subview that renders the Ingredients section: a four-state
//  view (idle / loading / loaded / failed) driven by IngredientsModel.
//
//  Depends on:     SwiftUI, IngredientsModel, IngredientsRow, the API
//                  library (for APIError pattern matching in the failed
//                  case).
//  Depended on by: PlanTabView (Plan tab root).
//  Why it exists:  dc-03 says a view body fits on screen; extract subviews
//                  aggressively. The state-machine switch and the reload
//                  button live here so PlanTabView stays a thin
//                  composition surface. The empty/error/load states are
//                  exhaustively rendered — the user never sees a frozen
//                  screen, even when the backend rejects the dev-token
//                  with 401 (the expected end-to-end behavior in Week 2
//                  per the work-prompt).

import API
import Domain
import SwiftUI

struct IngredientsListView: View {
    /// model is owned by the parent (PlanTabView holds it as @State).
    /// Receiving it as a plain `let` is the dc-03 pattern for a child
    /// view consuming a shared @Observable instance.
    let model: IngredientsModel

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                idleView
            case .loading:
                loadingView
            case let .loaded(items):
                loadedView(items: items)
            case let .failed(error):
                errorView(error: error)
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .navigationTitle("Ingredients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reload") {
                    Task { await model.load() }
                }
                .accessibilityLabel("Reload ingredients")
            }
        }
    }

    /// idleView is the pre-task state. It is rarely visible because
    /// `.task { }` fires immediately on appear; surfacing it is dc-00
    /// honesty about the load machine's existence.
    private var idleView: some View {
        ContentUnavailableView("Ingredients", systemImage: "tray")
    }

    /// loadingView shows the in-flight spinner. Keeping it a centered
    /// ProgressView (no surrounding chrome) prevents layout shift when
    /// the loaded list arrives.
    private var loadingView: some View {
        ProgressView("Loading ingredients…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading ingredients")
    }

    /// loadedView is the success state. An empty array shows a neutral
    /// empty state — distinct from the error state — so the user knows
    /// "we successfully asked, and there's nothing here yet."
    @ViewBuilder
    private func loadedView(items: [FoodItem]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No ingredients yet",
                systemImage: "leaf",
                description: Text("Track what's in your kitchen by chatting with the sous-chef.")
            )
        } else {
            List(items) { item in
                IngredientsRow(item: item)
            }
            .listStyle(.plain)
        }
    }

    /// errorView renders the failed state. The 401 path is special-cased
    /// to "Sign in to load" because that is the expected Week-2 outcome
    /// with the dev-token placeholder; Week 3's Auth wiring will replace
    /// the placeholder and this branch becomes a generic "session
    /// expired, sign in again" message.
    @ViewBuilder
    private func errorView(error: APIError) -> some View {
        if case .unauthorized = error {
            ContentUnavailableView(
                "Sign in to load",
                systemImage: "lock",
                description: Text("Ingredients require an authenticated session. Sign-in wiring lands in Week 3.")
            )
        } else {
            ContentUnavailableView(
                "Couldn’t load ingredients",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        }
    }
}
