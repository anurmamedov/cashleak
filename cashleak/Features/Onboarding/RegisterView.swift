import SwiftUI
import SwiftData

/// Creates a Firebase account and its matching local profile.
struct RegisterView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService
    @Query private var profiles: [UserProfile]

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var authenticationError: String?
    @State private var failures: [ProfileValidator.Failure] = []

    @FocusState private var focused: Field?

    private enum Field { case first, last, email, password, confirm }

    private var validationFailures: [ProfileValidator.Failure] {
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
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                } header: {
                    Text("About you")
                } footer: {
                    Text("Your name and email are used for your Firebase account and to personalise CashLeak.")
                }

                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focused = .confirm }

                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirm)
                        .submitLabel(.done)
                } header: {
                    Text("Account password")
                } footer: {
                    Text("Required for signing in. Firebase Authentication securely stores the credential; CashLeak never stores your password.")
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

                if let authenticationError {
                    Section {
                        Label(authenticationError, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "993C1D"))
                    }
                }
            }
            .navigationTitle("Register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create account") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear { focused = .first }
        }
    }

    @MainActor
    private func save() async {
        let found = validationFailures
        guard found.isEmpty else {
            withAnimation { failures = found }
            return
        }

        failures = []
        authenticationError = nil
        isSaving = true

        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            try await authentication.register(
                email: cleanEmail,
                password: password,
                firstName: cleanFirstName,
                lastName: cleanLastName
            )

            let profile: UserProfile
            if let existing = profiles.first {
                profile = existing
                profile.firstName = cleanFirstName
                profile.lastName = cleanLastName
                profile.email = cleanEmail
                profile.signInMethod = .email
            } else {
                profile = UserProfile(
                    firstName: cleanFirstName,
                    lastName: cleanLastName,
                    email: cleanEmail,
                    signInMethod: .email
                )
                context.insert(profile)
            }
            try context.save()
            dismiss()
        } catch {
            authenticationError = AuthenticationService.message(for: error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        isSaving = false
    }
}

extension ProfileValidator.Failure: Hashable {}
