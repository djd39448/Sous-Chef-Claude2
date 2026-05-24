//  MarkdownTests.swift
//
//  Stub Swift Testing suite for the Markdown library.
//
//  Depends on:     the Swift Testing framework and the Markdown library.
//  Depended on by: nothing — tests are leaves.
//  Why it exists:  dc-03 + dc-07 require `swift test` to be green. This file
//                  wires the Markdown test target so Week 3 can drop the
//                  canonical-recipe-subset corpus tests in without first
//                  fighting with the package layout.

@testable import Markdown
import Testing

@Suite("Markdown — foundation phase")
struct MarkdownFoundationTests {
    /// versionMarkerExists confirms the Markdown library compiled and linked.
    /// It will be removed when the real parser lands in Week 3.
    @Test func versionMarkerExists() {
        #expect(!SousChefMarkdownVersion.current.isEmpty)
    }
}
