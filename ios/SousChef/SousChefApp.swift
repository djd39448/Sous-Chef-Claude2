//  SousChefApp.swift
//
//  The @main entry point for the sous-chef-ios app.
//
//  Depends on:     SwiftUI for the App and WindowGroup primitives.
//  Depended on by: nothing — this file is the iOS app's entry point.
//  Why it exists:  every SwiftUI app needs exactly one `@main` App type. This
//                  one is intentionally thin: it picks the root scene based on
//                  whether the user is signed in. Per `track-ios.md` §3.9,
//                  state restoration (`@SceneStorage`) is wired in Phase F;
//                  in Week 1 the entry point shows the mocked LoginView so a
//                  cold launch on a simulator renders something coherent for
//                  the gate review. Real auth wires up in Week 2 (tasks
//                  A2–A4 of `track-ios.md` §5).

import SwiftUI

@main
struct SousChefApp: App {
    /// isSignedIn drives which root scene shows. In Week 1 the app launches
    /// signed-out, so LoginView is what the simulator opens to. A future
    /// AuthModel (Week 2) will replace this with an environment-injected
    /// session check.
    @State private var isSignedIn = false

    var body: some Scene {
        WindowGroup {
            if isSignedIn {
                RootView()
            } else {
                LoginView(onSignInSucceeded: { isSignedIn = true })
            }
        }
    }
}
