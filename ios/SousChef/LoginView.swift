//  LoginView.swift
//
//  The signed-out landing screen — mocked email + OTP flow for Week 1.
//
//  Depends on:     SwiftUI only. Week 2 (task A4 of `track-ios.md` §5) adds
//                  the Auth library and replaces the mocked action with a
//                  real `signInWithOTP` call per ADR-0003.
//  Depended on by: SousChefApp when the user is signed out.
//  Why it exists:  the dispatch brief calls for a mock-first login surface so
//                  the gate review can see the screen shape, copy, and
//                  navigation without blocking on Apple Developer enrollment.
//                  The "Send code" and "Verify" buttons show an alert
//                  explaining that real auth wires up in Week 2; they do not
//                  fake a successful sign-in silently. The Sign in with Apple
//                  control will be added in Week 2 (task A3) once the Service
//                  ID is provisioned.

import SwiftUI

/// LoginFlowStep tracks which half of the OTP flow is on screen — the user
/// types an email, taps Send code, then types the six-digit OTP. The mocked
/// surface only renders the two stages; no state crosses to a network call
/// in Week 1.
enum LoginFlowStep: Hashable {
    case enterEmail
    case enterCode
}

struct LoginView: View {
    /// onSignInSucceeded is the upward callback the app target uses to flip
    /// its `isSignedIn` state. In Week 1 this callback is **never invoked** —
    /// the mocked "Send code" and "Verify" buttons show an alert and do not
    /// transition the app to the signed-in state. The callback parameter
    /// exists so Week 2 (task A4 of `track-ios.md` §5) can wire the real
    /// `signInWithOTP` success path without changing this struct's signature.
    let onSignInSucceeded: () -> Void

    /// step is local state for which stage of the flow shows. The initial
    /// value is .enterEmail; previews override via the explicit initializer
    /// below so each key state (per dc-07) gets its own #Preview.
    @State private var step: LoginFlowStep
    @State private var email = ""
    @State private var code = ""
    @State private var mockAlertVisible = false

    /// The standard initializer — the app target always enters at
    /// `.enterEmail`. The `initialStep` initializer below is for previews
    /// only; production code never calls it.
    init(onSignInSucceeded: @escaping () -> Void) {
        self.onSignInSucceeded = onSignInSucceeded
        _step = State(initialValue: .enterEmail)
    }

    /// Preview-only initializer — lets a #Preview render the code-entry step
    /// directly so dc-07's "every view ships #Previews for key states" is
    /// honoured for both halves of the flow. Marked internal (no `public`
    /// or `private`) because previews live in the same module.
    init(onSignInSucceeded: @escaping () -> Void, initialStep: LoginFlowStep) {
        self.onSignInSucceeded = onSignInSucceeded
        _step = State(initialValue: initialStep)
        _email = State(initialValue: initialStep == .enterCode ? "dave@example.com" : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sous Chef")
                        .font(.largeTitle)
                        .bold()
                    Text("Sign in to plan meals, save recipes, and chat with your kitchen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Welcome")
                }

                switch step {
                case .enterEmail:
                    emailSection
                case .enterCode:
                    codeSection
                }

                Section {
                    Text(
                        """
                        Sign in with Apple wires up in Week 2 (task A3 of \
                        the iOS track plan), once Apple Developer \
                        enrollment and the Supabase provider are configured.
                        """
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Sign in with Apple")
                }
            }
            .navigationTitle("Sign in")
            .alert("Mocked in Week 1", isPresented: $mockAlertVisible) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Auth wires up against Supabase in Week 2. This run only renders the screen shape.")
            }
        }
    }

    /// emailSection is the first half of the flow — the email field and a
    /// "Send code" button. The button shows the mock alert and advances to
    /// the code step so a reviewer can walk both halves of the flow.
    private var emailSection: some View {
        Section {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Email address")
            Button {
                mockAlertVisible = true
                step = .enterCode
            } label: {
                Text("Send code")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty)
        } header: {
            Text("Email")
        } footer: {
            Text("We'll email you a six-digit code. (Real send wires up in Week 2.)")
        }
    }

    /// codeSection is the second half — the OTP field and a "Verify" button
    /// that shows the same mock alert. Acceptance of a real OTP lands in
    /// Week 2 (task A4 of `track-ios.md` §5).
    private var codeSection: some View {
        Section {
            TextField("Six-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .accessibilityLabel("One-time code")
            Button {
                mockAlertVisible = true
            } label: {
                Text("Verify")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.count < 6)
            Button("Back", role: .cancel) {
                step = .enterEmail
                code = ""
            }
        } header: {
            Text("Confirm code")
        }
    }
}

#Preview("Login — email step") {
    LoginView(onSignInSucceeded: {})
}

// The code-entry step is a distinct key state with its own affordances
// (numeric keypad, oneTimeCode content type, the Back button). dc-07 calls
// for a #Preview per key state; the preview-only initializer above lets us
// render this half without simulating taps.
#Preview("Login — code step") {
    LoginView(onSignInSucceeded: {}, initialStep: .enterCode)
}
