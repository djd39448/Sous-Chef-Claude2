//  APITests.swift
//
//  Stub Swift Testing suite for the API library.
//
//  Depends on:     the Swift Testing framework and the API library.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  dc-03 + dc-07 require `swift test` to be green. This file
//                  wires the API test target so Week 2's B1–B3 acceptance
//                  checks (DTO decoding fixtures, SSE chunk-buffer
//                  parameterized tests) drop straight in.

@testable import API
import Testing

@Suite("API — foundation phase")
struct APIFoundationTests {
    /// versionMarkerExists confirms the API library compiled and linked.
    /// It will be removed when the real APIClient lands in Week 2.
    @Test func versionMarkerExists() {
        #expect(!SousChefAPIVersion.current.isEmpty)
    }
}
