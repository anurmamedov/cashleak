import SwiftUI
import SwiftData
import AuthenticationServices

/// First run. Sign in with Apple, or continue with an email profile.
///
/// The copy has to do something unusual here: explain that signing in doesn't
/// create an account anywhere. Users have been trained that a sign-in screen
/// means a server, and this one doesn't — saying so up front is the difference
/// between a trust-building screen and a trust-destroying one.
struct WelcomeView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    @State private var isRegistering = false
    @State private var isSigningIn = false
    @State private var appleError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                dropMark
                Text("CashLeak")
                    .font(.system(size: 32, weight: .medium))
                Text("Most spending apps tell you where your money went. This one tells you what it cost you.")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    isRegistering = true
                } label: {
                    Text("Continue with email")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("I've been here before") {
                    isSigningIn = true
                }
                .font(.subheadline)
                .padding(.top, 2)

                if let appleError {
                    Text(appleError)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "993C1D"))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            // The line that stops a sign-in screen from reading as a data grab.
            Text("No account is created. Nothing is sent anywhere. Your name and email stay on this device and in your own iCloud.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 22)
                .padding(.bottom, 28)
        }
        .sheet(isPresented: $isRegistering) { RegisterView() }
        .sheet(isPresented: $isSigningIn) { SignInView() }
    }

    /// The real mark, not a stand-in symbol.
    ///
    /// The asset has a transparent ground and a knocked-out coin, so it sits on
    /// whatever is behind it — white here, the system background on the lock
    /// screen — without a plate around it.
    private var dropMark: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
    }

    // MARK: Apple

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleError = "Couldn't read the Apple response."
                return
            }

            // Apple sends the name and email exactly once, on first
            // authorisation. Every later sign-in returns only the user
            // identifier — so if this is dropped, it's gone for good.
            let first = credential.fullName?.givenName ?? ""
            let last = credential.fullName?.familyName ?? ""
            let email = credential.email ?? ""

            let profile = UserProfile(
                firstName: first,
                lastName: last,
                email: email,
                signInMethod: .apple,
                appleUserID: credential.user
            )
            context.insert(profile)
            try? context.save()

        case .failure(let error):
            // Cancelling isn't an error worth reporting back to the user.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            appleError = "Sign in with Apple didn't complete."
        }
    }
}
