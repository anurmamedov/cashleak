import SwiftUI

/// Turn the app lock on, change it, or turn it off.
///
/// Referenced from You › Passcode. The lock protects a local database on a
/// device that already has a passcode, so the copy avoids implying more
/// security than exists — and turning it off still asks for the current
/// password, because a lock anyone can silently remove isn't one.
struct LockSettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled = AppLock.isEnabled

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""

    @State private var message: String?
    @State private var messageIsError = true

    private var isTooShort: Bool {
        !new.isEmpty && new.count < ProfileValidator.minimumPasswordLength
    }

    private var canSave: Bool {
        guard new.count >= ProfileValidator.minimumPasswordLength, new == confirm else {
            return false
        }
        return isEnabled ? !current.isEmpty : true
    }

    var body: some View {
        List {
            if isEnabled {
                Section {
                    SecureField("Current password", text: $current)
                        .textContentType(.password)
                } footer: {
                    Text("Needed to change or remove the lock.")
                }
            }

            Section {
                SecureField(isEnabled ? "New password" : "Password", text: $new)
                    .textContentType(.newPassword)
                SecureField("Confirm", text: $confirm)
                    .textContentType(.newPassword)
            } header: {
                Text(isEnabled ? "Change" : "Set a password")
            } footer: {
                if isTooShort {
                    Text("At least \(ProfileValidator.minimumPasswordLength) characters.")
                } else if !confirm.isEmpty && new != confirm {
                    Text("Those don't match.")
                } else if AppLock.biometryIsAvailable {
                    Text("\(AppLock.biometryName) unlocks the app once a password is set. The password is the fallback.")
                } else {
                    Text("CashLeak asks for this when you open the app after backgrounding it.")
                }
            }

            Section {
                Button(isEnabled ? "Change password" : "Turn on lock", action: save)
                    .disabled(!canSave)

                if isEnabled {
                    Button("Turn off lock", role: .destructive, action: turnOff)
                        .disabled(current.isEmpty)
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(
                            messageIsError ? Color(hex: "993C1D") : Color(hex: "0F6E56")
                        )
                }
            }

            Section {
                Text("The password is stored as a salted hash in this device's Keychain and never leaves it. It locks the app — it doesn't encrypt your data, and it isn't an account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Passcode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        // Captured before the flag flips, or the confirmation always reads
        // "updated" — including the first time a lock is set.
        let wasEnabled = isEnabled

        if wasEnabled && !AppLock.verify(current) {
            show("That's not your current password.", isError: true)
            return
        }

        guard AppLock.setPassword(new) else {
            show("Couldn't save to the Keychain. Try again.", isError: true)
            return
        }

        clearFields()
        isEnabled = true
        show(wasEnabled ? "Password updated." : "Lock is on.", isError: false)
    }

    private func turnOff() {
        guard AppLock.verify(current) else {
            show("That's not your current password.", isError: true)
            return
        }

        AppLock.removePassword()
        clearFields()
        isEnabled = false
        show("Lock is off.", isError: false)
    }

    private func clearFields() {
        current = ""
        new = ""
        confirm = ""
    }

    private func show(_ text: String, isError: Bool) {
        messageIsError = isError
        withAnimation { message = text }
    }
}
