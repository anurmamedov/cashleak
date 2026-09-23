import SwiftUI

/// Shown when a passcode is set and the app has been backgrounded.
///
/// Biometrics are attempted immediately on appear, because a user who set up
/// Face ID expects the app to just open — making them tap a button first is the
/// kind of small friction that gets a lock turned off entirely.
struct LockScreenView: View {

    let onUnlock: () -> Void

    @State private var password = ""
    @State private var failedAttempt = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .accessibilityHidden(true)

            Text("CashLeak is locked")
                .font(.title3.weight(.medium))

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .focused($passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(attempt)

                if failedAttempt {
                    Text("That's not it.")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "993C1D"))
                }

                Button("Unlock", action: attempt)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)

                if AppLock.biometryIsAvailable {
                    Button {
                        Task { await tryBiometrics() }
                    } label: {
                        Label(
                            "Use \(AppLock.biometryName)",
                            systemImage: AppLock.biometryName == "Face ID" ? "faceid" : "touchid"
                        )
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            // Try biometrics first. If it fails or isn't set up, fall through
            // to the password field rather than sitting there doing nothing.
            if AppLock.biometryIsAvailable {
                if await AppLock.authenticateWithBiometrics() {
                    onUnlock()
                    return
                }
            }
            passwordFocused = true
        }
    }

    private func attempt() {
        if AppLock.verify(password) {
            password = ""
            failedAttempt = false
            onUnlock()
        } else {
            withAnimation { failedAttempt = true }
            password = ""
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func tryBiometrics() async {
        if await AppLock.authenticateWithBiometrics() {
            onUnlock()
        }
    }
}
