//  ImageCacheTests.swift
//
//  Stub Swift Testing suite for the ImageCache library.
//
//  Depends on:     the Swift Testing framework and the ImageCache library.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  dc-03 + dc-07 require `swift test` to be green. This file
//                  wires the ImageCache test target so Week 3 can drop in the
//                  LRU-eviction and cache-buster tests for ADR-0004 without
//                  scaffolding.

@testable import ImageCache
import Testing

@Suite("ImageCache — foundation phase")
struct ImageCacheFoundationTests {
    /// versionMarkerExists confirms the ImageCache library compiled and
    /// linked. It will be removed when the real cache lands in Week 3.
    @Test func versionMarkerExists() {
        #expect(!SousChefImageCacheVersion.current.isEmpty)
    }
}
