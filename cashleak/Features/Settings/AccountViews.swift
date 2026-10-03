import SwiftUI
import SwiftData
import PhotosUI
import AuthenticationServices

/// The app's version as people quote it to support: "1.0 (19)".
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private let brand = Color(hex: "C65A2E")
private let errorColor = Color(hex: "A32D2D")

// MARK: - Avatar

/// The profile photo if there is one, otherwise initials on CashLeak orange.
struct ProfileAvatar: View {

    let photo: Data?
    let initials: String
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(brand)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Edit profile

/// Your photo and name, and the way to change your email.
struct EditProfileView: View {

    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var didLoad = false

    /// The photo being edited — written to the profile only on Save, so Cancel
    /// really cancels.
    @State private var photo: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?

    private var initials: String {
        let first = firstName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let last = lastName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Optional. The system photo picker needs no permission — it
                // hands over only the one photo chosen.
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            ProfileAvatar(photo: photo, initials: initials, size: 96)
                            if isLoadingPhoto {
                                ProgressView()
                                    .frame(width: 96, height: 96)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }

                        HStack(spacing: 20) {
                            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                                Text(photo == nil ? "Add photo" : "Change photo")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderless)

                            if photo != nil {
                                Button("Remove", role: .destructive) {
                                    withAnimation { photo = nil }
                                }
                                .font(.subheadline)
                                .buttonStyle(.borderless)
                            }
                        }

                        if let photoError {
                            Text(photoError)
                                .font(.caption)
                                .foregroundStyle(errorColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                }

                if !profile.email.isEmpty {
                    Section {
                        if authentication.isAppleAccount {
                            LabeledContent("Email", value: profile.email)
                        } else {
                            NavigationLink {
                                ChangeEmailView(currentEmail: profile.email)
                            } label: {
                                LabeledContent("Email", value: profile.email)
                            }
                        }
                    } footer: {
                        Text(authentication.isAppleAccount
                             ? "Your email comes from your Apple ID. Change it in iPhone Settings › your name."
                             : "Your email is how you sign in.")
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .tint(brand)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                // Once only: coming back from Change email must not wipe a
                // name being edited.
                guard !didLoad else { return }
                didLoad = true
                firstName = profile.firstName
                lastName = profile.lastName
                photo = profile.photo
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
        }
    }

    private func save() {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.firstName = first
        profile.lastName = last
        profile.photo = photo
        try? context.save()
        // The name stays in the profile — on the phone and in iCloud — and is
        // not sent to the sign-in account (D-029).
        dismiss()
    }
}

extension EditProfileView {

    /// Loads the picked photo and shrinks it before it goes anywhere.
    @MainActor
    func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoError = nil
        defer {
            isLoadingPhoto = false
            pickerItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            photoError = "Couldn't open that photo. Try another one."
            return
        }
        // Off the main thread: decoding and resizing a 12 MP photo takes a beat.
        let prepared = await Task.detached(priority: .userInitiated) {
            ProfilePhoto.prepare(data)
        }.value

        guard let prepared else {
            photoError = "That doesn't look like a photo. Try another one."
            return
        }
        withAnimation { photo = prepared }
    }
}

// MARK: - Monthly take-home

/// One optional number: what lands in the account each month. Used only to
/// show spending as a share of it, and only when that says something (D-030).
struct TakeHomeView: View {

    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @FocusState private var focused: Bool

    private var amount: Double { LogWalletTransaction.parseAmount(amountText) }

    var body: some View {
        Form {
            Section {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.semibold))
                    .focused($focused)
            } header: {
                Text("What lands in your account each month")
                    .textCase(nil)
            } footer: {
                Text("After tax. A rough figure is fine — it's only used to show your spending as a share of it, based on the purchases in CashLeak. It stays on this iPhone and in your iCloud.")
            }

            if profile.monthlyTakeHome > 0 {
                Section {
                    Button("Remove", role: .destructive) {
                        profile.monthlyTakeHome = 0
                        try? context.save()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Without it, nothing in the app mentions take-home.")
                }
            }
        }
        .navigationTitle("Monthly take-home")
        .navigationBarTitleDisplayMode(.inline)
        .tint(brand)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profile.monthlyTakeHome = max(amount, 0)
                    try? context.save()
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(amount <= 0)
            }
        }
        .onAppear {
            if profile.monthlyTakeHome > 0 {
                amountText = String(format: "%.0f", profile.monthlyTakeHome)
            }
            focused = true
        }
    }
}

// MARK: - Change email

/// New email, confirmed by a link sent to it. Nothing changes until the link
/// is opened — the safe, current way to move an account to a new address.
struct ChangeEmailView: View {

    let currentEmail: String

    @EnvironmentObject private var authentication: AuthenticationService

    @State private var newEmail = ""
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var sentTo: String?

    private var cleanEmail: String {
        newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        Form {
            if let sentTo {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Check \(sentTo)")
                                .font(.headline)
                            Text("Open the link we sent to confirm it's yours. Your email changes when you do, and you'll sign in again with the new one.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(brand)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    LabeledContent("Current", value: currentEmail)
                    TextField("New email", text: $newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    HStack {
                        Group {
                            if showsPassword {
                                TextField("Current password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Current password", text: $password)
                            }
                        }
                        .textContentType(.password)

                        Button {
                            showsPassword.toggle()
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                    }
                } footer: {
                    Text("We'll send a link to the new address. Nothing changes until you open it.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(errorColor)
                    }
                }

                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() }
                            Text(isWorking ? "Sending…" : "Send confirmation link")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle("Change email")
        .navigationBarTitleDisplayMode(.inline)
        .tint(brand)
    }

    /// Checked here rather than by disabling the button, so tapping says
    /// what's missing.
    @MainActor
    private func send() async {
        guard ProfileValidator.isValidEmail(cleanEmail) else {
            error = "That email doesn't look right."
            return
        }
        guard cleanEmail != currentEmail.lowercased() else {
            error = "That's already your email."
            return
        }
        guard !password.isEmpty else {
            error = "Enter your current password."
            return
        }

        isWorking = true
        error = nil
        do {
            try await authentication.requestEmailChange(to: cleanEmail, password: password)
            withAnimation { sentTo = cleanEmail }
        } catch {
            let code = (error as NSError).code
            // 17007: the address already belongs to another account.
            self.error = code == 17007
                ? "That email is already used by another account."
                : "That password didn't work, or the connection dropped. Nothing changed."
            password = ""
        }
        isWorking = false
    }
}

// MARK: - Turn on Face ID sign-in

/// Saving the password for Face ID needs the password, and it's checked first
/// — a typo saved behind Face ID would fail silently on the next sign-in.
struct EnableFaceIDSignInView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService

    @State private var password = ""
    @State private var showsPassword = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Group {
                            if showsPassword {
                                TextField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit { Task { await turnOn() } }

                        Button {
                            showsPassword.toggle()
                        } label: {
                            Image(systemName: showsPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                    }
                } header: {
                    Text(authentication.email ?? "")
                        .textCase(nil)
                } footer: {
                    Text("Your password is kept only on this iPhone, locked by Face ID. It's never synced or sent anywhere except to sign you in.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(errorColor)
                    }
                }
            }
            .navigationTitle("Sign in with Face ID")
            .navigationBarTitleDisplayMode(.inline)
            .tint(brand)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isWorking ? "Checking…" : "Turn on") {
                        Task { await turnOn() }
                    }
                    .fontWeight(.semibold)
                    .disabled(password.isEmpty || isWorking)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func turnOn() async {
        guard !password.isEmpty, !isWorking, let email = authentication.email else { return }
        isWorking = true
        error = nil
        do {
            try await authentication.verifyPassword(password)
            if SavedSignIn.save(email: email.lowercased(), password: password) {
                dismiss()
            } else {
                error = "Couldn't save to this iPhone's Keychain. Check that a passcode is set."
            }
        } catch {
            self.error = "That password didn't work. Try again."
            password = ""
        }
        isWorking = false
    }
}

// MARK: - Delete account

/// Deleting the account, which App Review requires apps to offer in-app.
///
/// The account and the spending are separate things — the spending lives on
/// the phone and in the person's own iCloud — so the screen asks whether to
/// erase that too, and defaults to yes: someone deleting their account
/// usually means "remove me", and Apple's guidance is to delete the data an
/// account is tied to. Turning it off keeps everything on this iPhone.
struct DeleteAccountView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService

    @State private var eraseSpending = true
    @State private var password = ""
    @State private var showsPassword = false
    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var error: String?

    private var isApple: Bool { authentication.isAppleAccount }

    private var canDelete: Bool {
        !isWorking && (isApple || !password.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    point("person.crop.circle.badge.xmark", "Your CashLeak account is deleted. You can't sign in with it again.")
                    point("faceid", "Face ID sign-in and the app lock are turned off.")
                    point(
                        eraseSpending ? "trash" : "iphone",
                        eraseSpending
                            ? "Every purchase, goal, category and recurring bill is erased from this iPhone and your iCloud."
                            : "Your spending stays on this iPhone and in your iCloud."
                    )
                } header: {
                    Text("What happens")
                }

                Section {
                    Toggle("Also erase my spending", isOn: $eraseSpending)
                        .tint(errorColor)
                } footer: {
                    Text("Turn off to keep your purchases and goals on this iPhone. You can export them first from Profile › Export CSV.")
                }

                Section {
                    if isApple {
                        Label("You'll confirm with Apple.", systemImage: "apple.logo")
                            .font(.subheadline)
                    } else {
                        HStack {
                            Group {
                                if showsPassword {
                                    TextField("Password", text: $password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .textContentType(.password)

                            Button {
                                showsPassword.toggle()
                            } label: {
                                Image(systemName: showsPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
                        }
                    }
                } header: {
                    Text("Confirm it's you")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(errorColor)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirming = true
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() }
                            Text(isWorking ? "Deleting…" : "Delete account")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canDelete)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button(eraseSpending ? "Delete account and spending" : "Delete account", role: .destructive) {
                    Task { await delete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(errorColor)
        }
    }

    @MainActor
    private func delete() async {
        guard canDelete else { return }
        isWorking = true
        error = nil

        do {
            if isApple {
                let apple = AppleReauthentication()
                let credential = try await apple.run()
                try await authentication.deleteAppleAccount(credential: credential, rawNonce: apple.rawNonce)
            } else {
                try await authentication.deleteEmailAccount(password: password)
            }

            // Only after the account is really gone — a failed delete must
            // never take the spending with it.
            if eraseSpending {
                AccountData.eraseEverything(in: context)
            }
            AccountData.forgetIdentity(in: context)
        } catch {
            if (error as NSError).domain == ASAuthorizationError.errorDomain,
               (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                // Cancelled the Apple sheet. Nothing happened; nothing to say.
            } else if !isApple {
                self.error = "That password didn't work, or the connection dropped. Nothing was deleted."
                password = ""
            } else {
                self.error = "Apple couldn't confirm it. Nothing was deleted — try again."
            }
            isWorking = false
        }
    }
}
