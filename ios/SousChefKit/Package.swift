// swift-tools-version:6.0
//
//  Package.swift
//
//  The SousChefKit Swift Package — the non-UI half of the sous-chef-ios app.
//
//  Depends on:     the Swift 6 toolchain and Foundation only. No SwiftUI.
//                  Future targets will add `supabase-swift` to the Auth target
//                  once SIWA / OTP wiring lands in Week 2 (task A2 of
//                  `track-ios.md` §5).
//  Depended on by: the SousChef Xcode app target (`ios/SousChef/`). The app
//                  imports the per-library products listed below.
//  Why it exists:  dc-03 forbids `import SwiftUI` in model and service code.
//                  This package compiles without linking SwiftUI, so any stray
//                  `import SwiftUI` in domain, API, auth, markdown, or image-
//                  cache code becomes a build error rather than a code-review
//                  catch. The split into five library products mirrors the
//                  iOS track plan (`track-ios.md` §3.1) and lets the app
//                  import only what it needs at each call site.

import PackageDescription

let package = Package(
    name: "SousChefKit",
    // iOS is the production target (track-ios §3 / dc-03 baseline). macOS
    // is added so `swift test` on the dev host runs against the same
    // Foundation surface — URLSession.data(for:) requires macOS 12+, and
    // the Observation framework / @Observable macro the app uses needs
    // macOS 14+. These are test-time platform floors only; the iOS app
    // itself ships against iOS 17.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "API", targets: ["API"]),
        .library(name: "Auth", targets: ["Auth"]),
        .library(name: "Markdown", targets: ["Markdown"]),
        .library(name: "ImageCache", targets: ["ImageCache"]),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "API", dependencies: ["Domain"]),
        .target(name: "Auth", dependencies: ["Domain"]),
        .target(name: "Markdown"),
        .target(name: "ImageCache"),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "APITests", dependencies: ["API"]),
        .testTarget(name: "AuthTests", dependencies: ["Auth"]),
        .testTarget(name: "MarkdownTests", dependencies: ["Markdown"]),
        .testTarget(name: "ImageCacheTests", dependencies: ["ImageCache"]),
    ],
    swiftLanguageModes: [.v6]
)
