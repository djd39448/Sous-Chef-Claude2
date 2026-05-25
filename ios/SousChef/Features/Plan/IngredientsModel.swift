//  IngredientsModel.swift
//
//  The @Observable state object that owns the Plan tab's ingredients
//  list: a four-state load machine (idle → loading → loaded | failed)
//  driven by APIClient.ingredients().
//
//  Depends on:     SousChefKit's API and Domain libraries (APIClient,
//                  APIError, FoodItem). Observation (the @Observable
//                  macro). No SwiftUI import here even though the type
//                  lives in the app target — keeping it import-free
//                  makes future migration into a SousChefKit module
//                  easier if Week 3+ needs it shared.
//  Depended on by: IngredientsListView (the Plan tab's content view).
//  Why it exists:  dc-03 forbids ObservableObject + ViewModel-per-screen
//                  classes and requires @Observable state objects named
//                  for the domain. This file is the iOS track plan §3.3
//                  pattern realized for the ingredients read path: one
//                  observable type, one state enum, one load() method.
//                  Views render off `state`; the model never touches
//                  SwiftUI primitives. State mutations are serialized
//                  on the main actor so SwiftUI observers re-render
//                  predictably (dc-03's "approachable concurrency"
//                  default).

import API
import Domain
import Foundation
import Observation

/// IngredientsLoadState is the closed set of load-machine values the
/// view renders against. It is its own type (not a Result variant) so
/// the loaded case carries a typed array and the failed case carries
/// the typed APIError — pattern-matching at the view stays exhaustive.
public enum IngredientsLoadState: Sendable {
    /// idle is the initial state before any load is attempted. Views
    /// show a neutral placeholder.
    case idle
    /// loading is the state while a request is in flight. Views show
    /// a ProgressView.
    case loading
    /// loaded is the success state with the array the server returned.
    case loaded([FoodItem])
    /// failed is the terminal-but-retryable failure state. The
    /// APIError case lets the view show targeted messaging — e.g.
    /// "sign in to load" for .unauthorized.
    case failed(APIError)
}

/// IngredientsModel is the observable that the Plan tab uses to render
/// the user's CFO inventory. It owns the APIClient instance — for
/// Week 2 the work-prompt explicitly allows this `@State`-held client
/// pattern in lieu of the Auth-injected DI that lands once AuthModel
/// arrives in Week 3+.
@MainActor
@Observable
public final class IngredientsModel {
    /// state is the current load machine value. Views observe this
    /// property; mutations re-render only views that read it (the
    /// Observation-framework guarantee per dc-03).
    public private(set) var state: IngredientsLoadState = .idle

    /// client is the APIClient instance the model issues requests
    /// against. Held as a let so the same client survives across
    /// reload calls (preserving any URLSession-level caching the
    /// shared session does).
    private let client: APIClient

    /// init constructs the model with a pre-built APIClient. The view
    /// (which holds the model as @State) constructs both together.
    public init(client: APIClient) {
        self.client = client
    }

    /// load issues a fresh request and transitions the state machine.
    /// The method is idempotent at the view level — calling it while
    /// .loading restarts the cycle, which matches the user expectation
    /// of "tap reload during a load".
    public func load() async {
        state = .loading
        do {
            let items = try await client.ingredients()
            state = .loaded(items)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            // APIClient is documented to throw APIError exclusively;
            // any other Error here is a programmer-error contract
            // violation. Surface it through .failed so the user still
            // sees something rather than a frozen UI.
            state = .failed(.transport(URLError(.unknown)))
        }
    }
}
