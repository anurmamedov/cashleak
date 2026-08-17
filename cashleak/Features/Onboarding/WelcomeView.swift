import SwiftUI
import AuthenticationServices

/// Firebase-backed account entry. Financial data remains in private iCloud;
/// Firebase receives only the identity information needed to authenticate.
struct WelcomeView: View {

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authentication: AuthenticationService

    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isRecoveringPassword = false
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var appleError: String?
    @State private var appleNonce: String?

    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    dropMark

                    Text("Welcome to CashLeak")
                        .font(.system(size: 30, weight: .medium))

                    Text("See what your spending really cost you.")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)
                .padding(.bottom, 30)

                VStack(spacing: 14) {
                    TextField("Username (email)", text: $username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                        .welcomeFieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit(signIn)
                        .welcomeFieldStyle()

                    if let signInError {
                        Text(signInError)
                            .font(.caption)
                            .foregroundStyle(Color(hex: "993C1D"))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    Button(action: signIn) {
                        HStack {
                            if isSigningIn { ProgressView().tint(.white) }
                            Text(isSigningIn ? "Signing in…" : "Sign in")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "E05A47"))
                    .disabled(
                        username.trimmingCharacters(in: .whitespaces).isEmpty
                        || password.isEmpty
                        || isSigningIn
                    )

                    Button("Click to register") {
                        isRegistering = true
                    }
                    .font(.subheadline.weight(.medium))

                    Button("Forgot password?") {
                        isRecoveringPassword = true
                    }
                    .font(.subheadline)

                    HStack(spacing: 12) {
                        Divider()
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Divider()
                    }
                    .padding(.vertical, 2)

                    SignInWithAppleButton(.signIn) { request in
                        let nonce = AppleSignInNonce.make()
                        appleNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = AppleSignInNonce.hash(nonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if let appleError {
                        Text(appleError)
                            .font(.caption)
                            .foregroundStyle(Color(hex: "993C1D"))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                Text("Firebase securely handles sign-in. Your transactions remain in your private iCloud and are not sent to Firebase.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
            }
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $isRegistering) { RegisterView() }
        .sheet(isPresented: $isRecoveringPassword) { ForgotPasswordView() }
    }

    private var dropMark: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .frame(height: 112)
            .accessibilityHidden(true)
    }

    // MARK: Email sign-in

    private func signIn() {
        let normalizedUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        isSigningIn = true
        signInError = nil

        Task {
            do {
                try await authentication.signIn(email: normalizedUsername, password: password)
                password = ""
            } catch {
                signInError = AuthenticationService.message(for: error)
                password = ""
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isSigningIn = false
        }
    }

    // MARK: Apple

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                appleError = "Couldn't read the Apple response."
                return
            }
            guard let nonce = appleNonce else {
                appleError = "Sign in with Apple couldn't be verified. Please try again."
                return
            }

            appleError = nil
            Task {
                do {
                    try await authentication.signInWithApple(
                        credential: credential,
                        rawNonce: nonce
                    )
                } catch {
                    appleError = AuthenticationService.message(for: error)
                }
                appleNonce = nil
            }

        case .failure(let error):
            appleNonce = nil
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            appleError = "Sign in with Apple didn't complete."
        }
    }
}

private extension View {
    func welcomeFieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(.separator).opacity(0.45), lineWidth: 0.5)
            }
    }
}
