//  Markdown.swift
//
//  The Markdown library — the hand-rolled parser for the canonical recipe
//  markdown subset defined in the behavior spec §4.4.
//
//  Depends on:     Foundation only. No SwiftUI — the parser produces an AST
//                  (`[RecipeBlock]`) that the app target's SwiftUI views walk
//                  to render.
//  Depended on by: the SousChef app target's recipe and cookbook views.
//  Why it exists:  per `track-ios.md` §3.7, recipes follow a fixed markdown
//                  subset (`#`, `##`, `###`, `**bold**`, `- bullets`,
//                  `1. ordered`, plain paragraphs). SwiftUI's
//                  `AttributedString(markdown:)` handles only inline markdown
//                  and would miss block-level constructs; full CommonMark
//                  libraries are oversized for a known fixed format. A small
//                  hand-rolled parser keeps the renderer in this no-SwiftUI
//                  library and the view layer thin. Week 1 ships a marker
//                  only; task D4 of `track-ios.md` §5 populates the file in
//                  Week 3 alongside the recipe detail screen.

import Foundation

/// SousChefMarkdownVersion is a build-time identifier the app target can read
/// to confirm the Markdown library linked correctly. It will be replaced by
/// the real `RecipeBlock` AST and parser in Week 3.
public enum SousChefMarkdownVersion {
    /// current is the marker string the app prints at first launch.
    public static let current = "0.1.0-foundation"
}
