//  DomainTests.swift
//
//  Stub Swift Testing suite for the Domain library.
//
//  Depends on:     the Swift Testing framework and the Domain library.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  dc-03 requires Swift Testing for new tests and dc-07
//                  requires `swift test` to pass on every commit. This file
//                  ensures the test target is wired correctly so Week 2 can
//                  add real cases (decoding fixtures, week-date arithmetic)
//                  without first wrestling with the package layout.

@testable import Domain
import Testing

@Suite("Domain — foundation phase")
struct DomainFoundationTests {
    /// versionMarkerExists confirms the Domain library compiled and linked.
    /// It will be removed when real Domain types replace the marker.
    @Test func versionMarkerExists() {
        #expect(!SousChefDomainVersion.current.isEmpty)
    }
}
