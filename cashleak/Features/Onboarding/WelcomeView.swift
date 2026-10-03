import SwiftUI
import AuthenticationServices

/// Firebase-backed account entry. Financial data remains in private iCloud;
/// Firebase receives only the identity information needed to authenticate.
struct WelcomeView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var authentication: AuthenticationService

    @State private var username = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isRecoveringPassword = false
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var appleError: String?
    @State private var appleNonce: String?

    // Face ID sign-in (D-024). The orange button becomes "Sign in with Face ID"
    // once a sign-in has been saved on this phone.
    @State private var faceIDReady = SavedSignIn.isAvailable
    @State private var usingPassword = false
    @State private var rememberWithFaceID = true
    @State private var showsPassword = false
    @State private var didAutoTrigger = false

    /// Face ID is the main way in, and the password field is tucked away.
    private var faceIDMode: Bool { faceIDReady && !usingPassword }

    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    /// Sampled from LogoMark.png rather than picked by eye. Every touchable
    /// thing on this screen uses it — one orange, no near-misses.
    private let brand = Color(hex: "C65A2E")

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                form
                privacyLine
            }
        }
        .background(Color(.systemBackground))
        .scrollDismissesKeyboard(.interactively)
        // One tint for the whole screen. Without this the caret, the selection
        // handles and any unstyled control fall back to system blue, which is
        // the only colour on here that belongs to nobody.
        .tint(brand)
        .sheet(isPresented: $isRegistering) { RegisterView() }
        .sheet(isPresented: $isRecoveringPassword) { ForgotPasswordView() }
        .onAppear(perform: prepareFaceID)
    }

    // MARK: Header

    /// A tinted band carrying the mark and the promise.
    ///
    /// It runs to the top edge rather than sitting inside the safe area — a
    /// coloured block with a white strip above it reads as a mistake.
    private var header: some View {
        VStack(spacing: 10) {
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 76 : 116)
                .accessibilityHidden(true)

            Text("Welcome back")
                .font(.title2.weight(.medium))
                .foregroundStyle(headerTitleColor)
                .multilineTextAlignment(.center)

            Text("See what your spending really cost you.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(headerSubtitleColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, dynamicTypeSize.isAccessibilitySize ? 28 : 44)
        .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 24 : 34)
        .background(headerBackground)
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 10) {
            TextField("", text: $username, prompt: placeholder("name@email.com"))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focusedField, equals: .username)
                .onSubmit { focusedField = .password }
                .welcomeFieldStyle()
                .onChange(of: username) { _, newValue in
                    // A different email can't use the saved sign-in.
                    if faceIDReady,
                       newValue.trimmingCharacters(in: .whitespaces).lowercased() != SavedSignIn.savedEmail {
                        usingPassword = true
                    }
                }

            if !faceIDMode {
                passwordField

                // Beside the field it belongs to, rather than stacked under the
                // primary button competing with it.
                HStack {
                    Spacer()
                    Button("Forgot password?") { isRecoveringPassword = true }
                        .font(.footnote)
                        .foregroundStyle(brand)
                }
                .padding(.top, 2)

                // Only before a sign-in is saved. On by default: the whole
                // point is that this is the last time the password is typed.
                if !faceIDReady && SavedSignIn.biometryIsAvailable {
                    Toggle(isOn: $rememberWithFaceID) {
                        Label("Use Face ID next time", systemImage: "faceid")
                            .font(.subheadline)
                    }
                    .tint(brand)
                    .padding(.horizontal, 2)
                }
            }

            if let signInError {
                Text(signInError)
                    .font(.caption)
                    .foregroundStyle(errorColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Drawn by hand rather than with `.borderedProminent`. That style
            // picks its own height and corner radius, which is why it never
            // matched the Apple button sitting under it.
            Button {
                if faceIDMode {
                    Task { await signInWithFaceID() }
                } else {
                    signIn()
                }
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView().tint(.white)
                    } else if faceIDMode {
                        Image(systemName: "faceid")
                            .font(.title3)
                    }
                    Text(primaryTitle)
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight)
                .background(brand)
                .clipShape(RoundedRectangle(cornerRadius: controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)

            if faceIDReady {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        usingPassword.toggle()
                        signInError = nil
                    }
                    if usingPassword { focusedField = .password }
                } label: {
                    Label(
                        faceIDMode ? "Use password instead" : "Use Face ID instead",
                        systemImage: faceIDMode ? "key" : "faceid"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(brand)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }

            // No "or" divider. Two buttons stacked read as two ways in; a rule
            // between them implies a fork that isn't there.
            SignInWithAppleButton(.signIn) { request in
                let nonce = AppleSignInNonce.make()
                appleNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignInNonce.hash(nonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: controlHeight)
            .clipShape(RoundedRectangle(cornerRadius: controlRadius, style: .continuous))

            if let appleError {
                Text(appleError)
                    .font(.caption)
                    .foregroundStyle(errorColor)
                    .multilineTextAlignment(.center)
            }

            registerLine
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    /// One line, low in the hierarchy. Most people opening this screen already
    /// have an account; registration shouldn't compete with signing in.
    @ViewBuilder
    private var registerLine: some View {
        let prompt = Text("New here? ").foregroundStyle(.secondary)
        let action = Text("Create account")
            .foregroundStyle(brand)
            .fontWeight(.medium)

        Button {
            isRegistering = true
        } label: {
            (prompt + action)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    /// States what the user actually cares about — where their money data
    /// lives — rather than naming the vendor handling the password.
    private var privacyLine: some View {
        Text("Your spending stays on your phone and in your own iCloud.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 22)
            .padding(.bottom, 30)
    }

    // MARK: Password field

    /// The eye sits inside the field. Swapping SecureField for TextField drops
    /// focus, so it's put straight back.
    private var passwordField: some View {
        HStack(spacing: 8) {
            Group {
                if showsPassword {
                    TextField("", text: $password, prompt: placeholder("Password"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("", text: $password, prompt: placeholder("Password"))
                }
            }
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focusedField, equals: .password)
            .onSubmit(signIn)

            Button {
                let wasTyping = focusedField == .password
                showsPassword.toggle()
                if wasTyping { Task { @MainActor in focusedField = .password } }
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
        }
        .welcomeFieldStyle()
    }

    private var primaryTitle: String {
        if isSigningIn { return "Signing in…" }
        return faceIDMode ? "Sign in with Face ID" : "Sign in"
    }

    // MARK: Metrics

    /// One height and one radius for both sign-in buttons. They sit directly on
    /// top of each other, so any difference reads as a mistake rather than as
    /// hierarchy.
    private var controlHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 56 : 48
    }

    private var controlRadius: CGFloat { 11 }

    /// The one thing on this screen that deliberately isn't brand orange. An
    /// error rendered in the same colour as the button and the links reads as
    /// something to tap, not something that went wrong.
    private var errorColor: Color { Color(hex: "A32D2D") }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSigningIn
    }

    /// An explicit prompt for both fields. Left to the default, the email
    /// field's placeholder picks up AutoFill's tinted styling while the
    /// password field stays grey — the two never match.
    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundColor(Color(.placeholderText))
    }

    // MARK: Header palette

    private var headerBackground: Color {
        colorScheme == .dark ? Color(hex: "2A1712") : Color(hex: "FAECE7")
    }

    private var headerTitleColor: Color {
        colorScheme == .dark ? Color(hex: "F5C4B3") : Color(hex: "4A1B0C")
    }

    private var headerSubtitleColor: Color {
        colorScheme == .dark ? Color(hex: "F0997B") : brand
    }

    // MARK: Email sign-in

    private func signIn() {
        guard !isSigningIn else { return }

        // Checked here rather than by disabling the button. A dead grey control
        // gives no reason and can't be tapped to find one out; this says what's
        // missing the moment someone asks.
        guard canSubmit else {
            withAnimation {
                signInError = username.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Enter your email address."
                    : "Enter your password."
            }
            focusedField = username.trimmingCharacters(in: .whitespaces).isEmpty
                ? .username
                : .password
            return
        }

        let normalizedUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        isSigningIn = true
        signInError = nil

        // Captured before the await: the screen is replaced the moment sign-in
        // succeeds, and the save has to happen with the values that worked.
        let typedPassword = password
        let shouldSave = SavedSignIn.biometryIsAvailable
            && (rememberWithFaceID || (faceIDReady && normalizedUsername == SavedSignIn.savedEmail))

        Task {
            do {
                try await authentication.signIn(email: normalizedUsername, password: typedPassword)
                // Saved only after Firebase accepted it — a typo is never kept.
                if shouldSave {
                    SavedSignIn.save(email: normalizedUsername, password: typedPassword)
                }
                password = ""
            } catch {
                signInError = AuthenticationService.message(for: error)
                password = ""
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isSigningIn = false
        }
    }

    // MARK: Face ID sign-in

    /// Fills the saved email and, once per appearance, starts Face ID by itself
    /// — the screen is already saying "Sign in with Face ID", so making someone
    /// tap first is a wasted step.
    private func prepareFaceID() {
        faceIDReady = SavedSignIn.isAvailable
        guard faceIDReady, let email = SavedSignIn.savedEmail else { return }
        username = email

        guard !didAutoTrigger else { return }
        didAutoTrigger = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if faceIDMode { await signInWithFaceID() }
        }
    }

    @MainActor
    private func signInWithFaceID() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil

        switch await SavedSignIn.load() {
        case let .success(email, savedPassword):
            do {
                try await authentication.signIn(email: email, password: savedPassword)
            } catch {
                // Most likely the password was changed somewhere else. Keep the
                // saved sign-in; a successful password sign-in replaces it.
                withAnimation {
                    usingPassword = true
                    signInError = "Face ID couldn't sign you in — your password may have changed. Sign in with it once and Face ID will work again."
                }
                focusedField = .password
            }
        case .cancelled:
            break
        case .unavailable:
            withAnimation {
                faceIDReady = false
                usingPassword = true
                signInError = "Face ID changed on this iPhone, so it was turned off for sign-in. Sign in with your password to set it up again."
            }
            focusedField = .password
        }

        isSigningIn = false
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

/// Warm off-white in light mode, warm near-black in dark. Both are the coral
/// ramp at very low saturation, so the fields belong to the header rather than
/// looking like stock system chrome.
private var fieldFill: Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.10, blue: 0.09, alpha: 1)
            : UIColor(red: 0.98, green: 0.96, blue: 0.95, alpha: 1)
    })
}

private extension View {
    func welcomeFieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            // A faint warm wash, not white. On a white page an outlined-only
            // field disappears into the background; a neutral grey fill reads
            // as disabled. This sits between the two and stays in the palette.
            .background(fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            }
    }
}
