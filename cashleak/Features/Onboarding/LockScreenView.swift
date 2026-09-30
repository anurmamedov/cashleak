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

            if !AppLock.hasPassword {
                deviceUnlock
            } else {
                passwordUnlock
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            // Face ID first, straight away. With no app password set, the
            // system falls back to the iPhone passcode by itself.
            if !AppLock.hasPassword {
                if await AppLock.authenticateWithDevice() { onUnlock() }
                return
            }
            // Password lock: try biometrics, then fall through to the field
            // rather than sitting there doing nothing.
            if AppLock.biometryIsAvailable {
                if await AppLock.authenticateWithBiometrics() {
                    onUnlock()
                    return
                }
            }
            passwordFocused = true
        }
    }

    /// Face ID lock with no app password — one button, in case the automatic
    /// attempt was cancelled.
    private var deviceUnlock: some View {
        Button {
            Task { if await AppLock.authenticateWithDevice() { onUnlock() } }
        } label: {
            Label(
                "Unlock with \(AppLock.biometryName)",
                systemImage: AppLock.biometryName == "Touch ID" ? "touchid" : "faceid"
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(hex: "C65A2E"))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
    }

    private var passwordUnlock: some View {
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
