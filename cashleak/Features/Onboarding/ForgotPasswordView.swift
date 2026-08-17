import SwiftUI

/// Sends Firebase Authentication's password-reset email.
struct ForgotPasswordView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService

    @State private var username = ""
    @State private var message: String?
    @State private var isResetting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username (email)", text: $username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Reset your password")
                } footer: {
                    Text("Firebase will send a secure password-reset link to this email address.")
                }

                Section {
                    Button {
                        Task { await resetPassword() }
                    } label: {
                        HStack {
                            Text("Send reset email")
                            Spacer()
                            if isResetting { ProgressView() }
                        }
                    }
                    .disabled(
                        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isResetting
                    )
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(message.hasPrefix("If an account") ? .secondary : Color(hex: "993C1D"))
                    }
                }
            }
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func resetPassword() async {
        let normalizedUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        isResetting = true
        message = nil

        do {
            try await authentication.sendPasswordReset(email: normalizedUsername)
            // Keep this response generic so the screen does not reveal whether
            // a particular email address has an account.
            message = "If an account exists for that email, a reset link is on its way."
        } catch {
            message = AuthenticationService.message(for: error)
        }
        isResetting = false
    }
}
