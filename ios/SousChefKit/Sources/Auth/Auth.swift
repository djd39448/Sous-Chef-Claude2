//  Auth.swift
//
//  The Auth library — Supabase-backed session and JWT management for the
//  sous-chef-ios app.
//
//  Depends on:     Foundation, Domain (for the user identity value), and
//                  (Week 2) the `supabase-swift` SDK for Sign in with Apple
//                  and email/OTP flows per ADR-0003.
//  Depended on by: the API library (consumes the JWT provider closure) and
//                  the SousChef app target's LoginView and SousChefApp entry
//                  point.
//  Why it exists:  per `track-ios.md` §3.3, the AuthModel owns the current
//                  Supabase session and exposes async sign-in / sign-out
//                  methods plus a token-refresh path the API client calls on
//                  401 (`contract/contract.md` §2.3). The model lives in this
//                  library so it can be unit-tested without booting any UI.
//                  Week 1 ships a marker only; tasks A2–A4 of `track-ios.md`
//                  §5 populate the file in Week 2 once Dave completes the
//                  Apple Developer enrollment listed in §9 of the plan.

import Foundation

/// SousChefAuthVersion is a build-time identifier the app target can read to
/// confirm the Auth library linked correctly. It will be replaced by the real
/// AuthModel in Week 2.
public enum SousChefAuthVersion {
    /// current is the marker string the app prints at first launch.
    public static let current = "0.1.0-foundation"
}
