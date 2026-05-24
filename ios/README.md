# `ios/` — SwiftUI iOS app

The native iOS app. Renders the chat, plan, calendar, recipe, cookbook,
and shopping surfaces against the backend's contract.

## Stack

- **Language:** Swift 6 (warning-free under complete concurrency checking).
- **UI:** SwiftUI.
- **Deployment target:** iOS 17.0 (the `@Observable` macro is core to the
  view-model pattern per `dc-03`).
- **Auth:** Sign in with Apple + Supabase email/OTP via the Supabase iOS
  SDK (ADR-0003).
- **Navigation:** `NavigationStack` with typed `NavigationPath` per tab.
  No Universal Links in v1 (ADR-0005).
- **Image cache:** on-device LRU disk cache for cookbook images, 128 MB
  cap, evicts by access time (ADR-0004).
- **Streaming:** consumes the backend's SSE via `URLSession.bytes`.

## Track plan (authoritative)

[`plan/track-ios.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/plan/track-ios.md)
— foundations → API client + codable models → chat with SSE →
meal-plan view → recipe detail → calendar → cookbook → shopping →
polish + state restoration + image cache.

## Contract

[`contract/contract.md`](https://github.com/djd39448/DevCore/blob/main/.devcore/memory/contract/contract.md)
§5 (REST surface), §6 (SSE), and §7 (AI tool-calling — tool-result events
the app renders) are the implementation targets. The behavior spec
§3 (Behaviors per surface) and §4.4 (canonical recipe markdown) are the
view requirements.

## Architecture (planned)

Hybrid: one Xcode app target plus one in-repo Swift Package
(`SousChefKit`) split into five library targets:

```
ios/
  SousChef/                          ← Xcode app target (SwiftUI only)
    SousChefApp.swift                ← @main
    Views/                           ← SwiftUI views, per tab
  SousChefKit/                       ← Swift Package
    Sources/
      Domain/                        ← entities, value types — no SwiftUI
      API/                           ← URLSession client + codable models
      Auth/                          ← Supabase auth wrapper
      Markdown/                      ← hand-rolled recipe markdown parser
      ImageCache/                    ← NSCache + disk LRU
    Tests/                           ← XCTest / Swift Testing
  Package.swift
  .swiftformat                       ← shared with DevCore desktop
  .swiftlint.yml                     ← shared with DevCore desktop
```

The split is deliberate: the package targets do **not** link SwiftUI, so
`dc-03`'s "model and service types **never** `import SwiftUI`" rule is a
compile-time guarantee, not a code-review item.

View-model pattern: Model-View with `@Observable` macro per `dc-03`. No
`…ViewModel` classes, no `ObservableObject`.

## Standards

[`CODING_STANDARDS.md`](https://github.com/djd39448/DevCore/blob/main/CODING_STANDARDS.md)
`dc-03` (Swift / SwiftUI) governs every line; `dc-06` (macOS / Xcode)
governs the build environment.
