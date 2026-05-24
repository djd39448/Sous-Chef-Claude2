//  API.swift
//
//  The API library — the HTTP and SSE client for the Go backend at
//  `/api/kitchen/*`.
//
//  Depends on:     Foundation (URLSession), Domain (mapping wire DTOs into
//                  domain models).
//  Depended on by: the SousChef app target (every screen that reads or writes
//                  data) and the Auth library (the JWT provider closure is
//                  injected into APIClient).
//  Why it exists:  the contract (`contract/contract.md` §5, §6) specifies one
//                  HTTP surface and one SSE wire format. Per `track-ios.md`
//                  §3.4 and dc-03, all HTTP access lives in a single
//                  protocol-defined client backed by URLSession — never
//                  scattered in views. This target hosts that client, the
//                  Codable DTOs that mirror wire shapes verbatim, the SSE
//                  parser with the chunk-buffer rule from contract §6.4, and
//                  the typed APIError set keyed on the contract's normative
//                  error codes (§3.5). Week 1 ships a marker only; tasks
//                  B1–B3 of `track-ios.md` §5 populate the file in Week 2.

import Foundation

/// SousChefAPIVersion is a build-time identifier the app target can read to
/// confirm the API library linked correctly. It will be replaced by the real
/// APIClient actor in Week 2.
public enum SousChefAPIVersion {
    /// current is the marker string the app prints at first launch.
    public static let current = "0.1.0-foundation"
}
