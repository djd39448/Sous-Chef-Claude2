//  AuthTests.swift
//
//  Stub Swift Testing suite for the Auth library.
//
//  Depends on:     the Swift Testing framework and the Auth library.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  dc-03 + dc-07 require `swift test` to be green. This file
//                  wires the Auth test target so Week 2's AuthModel tests
//                  (session refresh, JWT provider correctness) can be added
//                  without scaffolding.

@testable import Auth
import Testing

@Suite("Auth — foundation phase")
struct AuthFoundationTests {
    /// versionMarkerExists confirms the Auth library compiled and linked.
    /// It will be removed when the real AuthModel lands in Week 2.
    @Test func versionMarkerExists() {
        #expect(!SousChefAuthVersion.current.isEmpty)
    }
}
