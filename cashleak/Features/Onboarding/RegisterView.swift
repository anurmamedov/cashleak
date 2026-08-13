import SwiftUI
import SwiftData

/// First name, last name, email, password.
///
/// The password sets an app lock rather than an account credential — there's
/// nothing to authenticate against. It's optional for exactly that reason:
/// forcing a password that protects nothing would be security theatre, and the
/// device passcode already does the real work.
struct RegisterView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var wantsPasscode = false
    @State private var failures: [ProfileValidator.Failure] = []

    @FocusState private var focused: Field?

    private enum Field { case first, last, email, password, confirm }

    private var validationFailures: [ProfileValidator.Failure] {
        guard wantsPasscode else {
            return ProfileValidator.validateRegistration(
                firstName: firstName, lastName: lastName, email: email,
                password: String(repeating: "x", count: ProfileValidator.minimumPasswordLength),
                confirmPassword: String(repeating: "x", count: ProfileValidator.minimumPasswordLength)
            )
        }
        return ProfileValidator.validateRegistration(
            firstName: firstName, lastName: lastName, email: email,
            password: password, confirmPassword: confirmPassword
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .focused($focused, equals: .first)
                        .submitLabel(.next)
                        .onSubmit { focused = .last }

                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .focused($focused, equals: .last)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.done)
                } header: {
                    Text("About you")
                } footer: {
                    Text("Used to personalise the app. Never sent anywhere — there's no CashLeak server to send it to.")
                }

                Section {
                    Toggle("Require a passcode", isOn: $wantsPasscode.animation())

                    if wantsPasscode {
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .password)

                        SecureField("Confirm password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .confirm)

                        if AppLock.biometryIsAvailable {
                            Label(
                                "\(AppLock.biometryName) will work too",
                                systemImage: AppLock.biometryName == "Face ID" ? "faceid" : "touchid"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Lock")
                } footer: {
                    Text(wantsPasscode
                         ? "Stored as a salted hash in the device Keychain. The password itself is never saved, and it can't be recovered — only reset by signing out."
                         : "Optional. Your phone's own passcode already protects the app; this adds a second one if you share the device.")
                }

                if !failures.isEmpty {
                    Section {
                        ForEach(failures, id: \.self) { failure in
                            Label(
                                ProfileValidator.message(for: failure),
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "993C1D"))
                        }
                    }
                }
            }
            .navigationTitle("Get started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                }
            }
            .onAppear { focused = .first }
        }
    }

    private func save() {
        let found = validationFailures
        guard found.isEmpty else {
            withAnimation { failures = found }
            return
        }

        if wantsPasscode {
            AppLock.setPassword(password)
        }

        let profile = UserProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            signInMethod: .email
        )
        context.insert(profile)
        try? context.save()

        dismiss()
    }
}

extension ProfileValidator.Failure: Hashable {}

/// Returning users. There's no credential to check against a server, so this
/// verifies the email matches the profile already on the device — and says so,
/// rather than implying a lookup that isn't happening.
struct SignInView: View {

    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var email = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Checks against the profile on this device. Nothing is looked up online.")
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "993C1D"))
                    }
                }

                Section {
                    Text("If you've reinstalled the app, your data comes back from your own iCloud automatically — there's no account to restore.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Welcome back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { attempt() }
                }
            }
        }
    }

    private func attempt() {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()

        guard !profiles.isEmpty else {
            error = "No profile on this device yet. Use Get started instead."
            return
        }
        guard profiles.contains(where: { $0.email.lowercased() == trimmed }) else {
            error = "That email doesn't match the profile on this device."
            return
        }

        dismiss()
    }
}
