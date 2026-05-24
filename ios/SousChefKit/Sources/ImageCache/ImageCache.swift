//  ImageCache.swift
//
//  The ImageCache library — on-device LRU cache for cookbook images.
//
//  Depends on:     Foundation (NSCache, FileManager) only. UIKit's low-memory
//                  notification is observed via NotificationCenter without
//                  importing UIKit; the constant name is referenced as a
//                  string in Week 3 to keep this target SwiftUI- and
//                  UIKit-free.
//  Depended on by: the SousChef app target's cookbook list and recipe views.
//  Why it exists:  per ADR-0004 and `track-ios.md` §3.6, cookbook images are
//                  cached on-device with a 128 MB disk cap, evicted by LRU
//                  access time, keyed by `cookbook_recipes.id` with the
//                  `?v=<unix>` cache-buster honored. Hosting the cache here
//                  keeps it testable without booting the app and prevents
//                  SwiftUI leakage into model code (dc-03). Week 1 ships a
//                  marker only; task E1 of `track-ios.md` §5 populates the
//                  file in Week 3.

import Foundation

/// SousChefImageCacheVersion is a build-time identifier the app target can
/// read to confirm the ImageCache library linked correctly. It will be
/// replaced by the real `ImageCache` actor in Week 3.
public enum SousChefImageCacheVersion {
    /// current is the marker string the app prints at first launch.
    public static let current = "0.1.0-foundation"
}
