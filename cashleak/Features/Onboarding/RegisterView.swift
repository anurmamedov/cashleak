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
    @State private var showsPassword = false
    @State private var showsConfirmPassword = false

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
                    Text("Your name and email are used for your CashLeak account and to personalise the app.")
                }

                Section {
                    passwordField(
                        "Password",
                        text: $password,
                        field: .password,
                        isVisible: $showsPassword,
                        submitLabel: .next
                    ) { focused = .confirm }

                    passwordField(
                        "Confirm password",
                        text: $confirmPassword,
                        field: .confirm,
                        isVisible: $showsConfirmPassword,
                        submitLabel: .done
                    ) { focused = nil }
                } header: {
                    Text("Account password")
                } footer: {
                    Text("Used only to sign in. If you turn on Face ID sign-in later, it's kept on this iPhone, locked by Face ID.")
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

    /// A password field with a show / hide eye inside it, on the right.
    ///
    /// Typos in a password nobody can see are the most common reason a new
    /// account can't sign in again. The eye swaps a `SecureField` for a
    /// `TextField`; that swap drops keyboard focus, so it's put straight back
    /// when the field was the one being typed in.
    private func passwordField(
        _ title: String,
        text: Binding<String>,
        field: Field,
        isVisible: Binding<Bool>,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(title, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(title, text: text)
                }
            }
            .textContentType(.newPassword)
            .focused($focused, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)

            Button {
                let wasTyping = focused == field
                isVisible.wrappedValue.toggle()
                if wasTyping {
                    Task { @MainActor in focused = field }
                }
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            // Borderless so a tap on the eye doesn't also count as a tap on
            // the whole Form row.
            .buttonStyle(.borderless)
            .accessibilityLabel(isVisible.wrappedValue ? "Hide password" : "Show password")
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
