import SwiftUI
import SwiftData

/// Capture status first, preferences second, data last.
///
/// Capture leads because it's the thing users will be confused about, and
/// because stating what *won't* be captured up front is the honesty the whole
/// product rests on.
struct YouView: View {

    @Environment(\.modelContext) private var context

    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query(sort: \CardAutomation.createdAt) private var cards: [CardAutomation]
    @Query private var trips: [Trip]
    @Query private var rules: [RecurringRule]
    @Query private var profiles: [UserProfile]

    @State private var isAddingCard = false
    @State private var newCardLabel = ""
    @State private var exportURL: URL?
    @State private var accent = AppSettings.accentHex
    @State private var currency = AppSettings.currencyCode
    @State private var notificationTime = Date.now

    private var supersededCount: Int { transactions.filter(\.isSuperseded).count }
    private var activeCount: Int { transactions.count - supersededCount }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                captureSection
                coverageNote
                preferencesSection
                dataSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("You")
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .alert("Add a card", isPresented: $isAddingCard) {
                TextField("Visa ···6411", text: $newCardLabel)
                Button("Cancel", role: .cancel) { newCardLabel = "" }
                Button("Add") { addCard() }
            } message: {
                Text("Name it however you'll recognise it. CashLeak can't read your Wallet, so this is just a label.")
            }
            .onAppear(perform: loadNotificationTime)
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        Section {
            if let profile = profiles.first {
                HStack(spacing: 12) {
                    Text(profile.initials)
                        .font(.subheadline.weight(.medium))
                        .frame(width: 42, height: 42)
                        .background(Color(hex: AppSettings.accentHex).opacity(0.18))
                        .foregroundStyle(Color(hex: AppSettings.accentHex))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.fullName.isEmpty ? "You" : profile.fullName)
                            .font(.body.weight(.medium))
                        if !profile.email.isEmpty {
                            Text(profile.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Signed in with \(profile.signInMethod.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)

                NavigationLink {
                    LockSettingsView()
                } label: {
                    HStack {
                        Label("Passcode", systemImage: "lock")
                        Spacer()
                        Text(AppLock.isEnabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    signOut(profile)
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } footer: {
            Text("Signing out clears your profile and passcode from this device. Your transactions stay — they live in your own iCloud, not in an account.")
        }
    }

    private func signOut(_ profile: UserProfile) {
        AppLock.removePassword()
        context.delete(profile)
        try? context.save()
    }

    // MARK: Capture

    private var captureSection: some View {
        Section("Capture") {
            ForEach(cards) { card in
                NavigationLink {
                    WalletSetupView()
                } label: {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.label)
                                .font(.subheadline)
                            Text(card.statusText)
                                .font(.caption)
                                .foregroundStyle(statusColor(card))
                        }
                        Spacer()
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        context.delete(card)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        card.isConfigured.toggle()
                        try? context.save()
                    } label: {
                        Label(card.isConfigured ? "Mark unset" : "Mark set up", systemImage: "checkmark")
                    }
                    .tint(Color(hex: "1D9E75"))
                }
            }

            Button {
                isAddingCard = true
            } label: {
                Label("Add a card", systemImage: "plus")
            }

            NavigationLink {
                RecurringRulesView()
            } label: {
                Label("Recurring · \(rules.count) rules", systemImage: "repeat")
            }

            NavigationLink {
                TripsListView()
            } label: {
                Label("Trips · \(trips.count)", systemImage: "airplane")
            }

            NavigationLink {
                CaptureLogView()
            } label: {
                Label("Capture log", systemImage: "list.bullet.rectangle")
            }
        }
    }

    private func statusColor(_ card: CardAutomation) -> Color {
        if !card.isConfigured { return Color(hex: "993C1D") }
        if card.looksStale { return Color(hex: "854F0B") }
        return Color(hex: "0F6E56")
    }

    private var coverageNote: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("What won't be captured")
                    .font(.subheadline.weight(.medium))
                Text("Physical card taps, in-app and web purchases, e-transfers and cash. Recurring rules cover the predictable rest; anything else takes five seconds to add by hand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Preferences

    private var preferencesSection: some View {
        Section("Preferences") {
            HStack {
                Text("Accent")
                Spacer()
                HStack(spacing: 8) {
                    ForEach(AccentOption.allCases) { option in
                        Circle()
                            .fill(Color(hex: option.hex))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: accent == option.hex ? 2 : 0)
                                    .padding(-3)
                            )
                            .opacity(accent == option.hex ? 1 : 0.4)
                            .onTapGesture {
                                accent = option.hex
                                AppSettings.accentHex = option.hex
                            }
                            .accessibilityLabel(option.name)
                    }
                }
            }

            DatePicker("Daily summary", selection: $notificationTime, displayedComponents: .hourAndMinute)
                .onChange(of: notificationTime) { _, newValue in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    AppSettings.notificationHour = parts.hour ?? 21
                    AppSettings.notificationMinute = parts.minute ?? 0
                }

            Picker("Currency", selection: $currency) {
                ForEach(currencyOptions, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .onChange(of: currency) { _, newValue in
                AppSettings.currencyCode = newValue
            }

            NavigationLink {
                CategoriesView()
            } label: {
                HStack {
                    Text("Categories")
                    Spacer()
                    Text("\(categories.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currencyOptions: [String] {
        var options = AppSettings.offeredCurrencies
        if !options.contains(currency) { options.insert(currency, at: 0) }
        return options
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            LabeledContent("Transactions", value: "\(activeCount)")
            if supersededCount > 0 {
                LabeledContent("Merged duplicates", value: "\(supersededCount)")
            }

            Button {
                export()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }

            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "lock")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything lives on this device and in your own iCloud. There is no CashLeak server.")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Button("Generate 4 months of data") {
                SeedData.generate(months: 4, in: context)
            }
            Button("Simulate a 2-week L1 trial") {
                SeedData.clearTransactions(in: context)
                SeedData.generateTwoWeekTrial(in: context)
            }
            Button("Run bank alert samples") {
                for sample in BankAlertParser.sampleAlerts {
                    guard let parsed = BankAlertParser.parse(sample.text) else { continue }
                    TransactionIngest.ingest(
                        amount: parsed.amount,
                        merchant: parsed.merchant,
                        source: .bankAlert,
                        into: context
                    )
                }
            }
            Button("Simulate an Apple Pay tap") {
                TransactionIngest.ingest(
                    amount: Double.random(in: 4...60).rounded(),
                    merchant: ["Blue Bottle", "Uber Eats", "Loblaws", "Shell"].randomElement(),
                    source: .applePay,
                    into: context
                )
            }
            Button("Clear transactions", role: .destructive) {
                SeedData.clearTransactions(in: context)
            }
        }
    }
    #endif

    // MARK: Actions

    private func addCard() {
        let trimmed = newCardLabel.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.insert(CardAutomation(label: trimmed))
        try? context.save()
        newCardLabel = ""
    }

    private func export() {
        exportURL = try? CSVExport.writeTemporaryFile(from: transactions)
    }

    private func loadNotificationTime() {
        var parts = DateComponents()
        parts.hour = AppSettings.notificationHour
        parts.minute = AppSettings.notificationMinute
        notificationTime = Calendar.current.date(from: parts) ?? .now
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Categories. Deleting one must not take its transactions with it.
struct CategoriesView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    var body: some View {
        List {
            ForEach(categories) { category in
                HStack {
                    Image(systemName: category.icon)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 26)
                    Text(category.name)
                    Spacer()
                    Text(category.kind == .need ? "Need" : "Want")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(categories[index])
        }
        try? context.save()
    }
}

/// Turn the passcode on or off after registration.
struct LockSettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled = AppLock.isEnabled
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Require a passcode", isOn: $isEnabled.animation())
                    .onChange(of: isEnabled) { _, on in
                        if !on {
                            AppLock.removePassword()
                            password = ""
                            confirmPassword = ""
                            error = nil
                        }
                    }
            } footer: {
                Text("Your phone's own passcode already protects the app. This adds a second one, useful if you share the device.")
            }

            if isEnabled && !AppLock.isEnabled {
                Section {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm", text: $confirmPassword)
                        .textContentType(.newPassword)
                    Button("Set passcode") { set() }
                        .disabled(password.isEmpty)

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "993C1D"))
                    }
                } footer: {
                    Text("Stored as a salted hash in the device Keychain. It can't be recovered — only replaced by turning this off and on again.")
                }
            }

            if AppLock.isEnabled && AppLock.biometryIsAvailable {
                Section {
                    Label("\(AppLock.biometryName) unlocks the app too", systemImage: "faceid")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Passcode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func set() {
        guard password.count >= ProfileValidator.minimumPasswordLength else {
            error = ProfileValidator.message(for: .passwordTooShort)
            return
        }
        guard password == confirmPassword else {
            error = ProfileValidator.message(for: .passwordMismatch)
            return
        }
        AppLock.setPassword(password)
        error = nil
        dismiss()
    }
}

/// The privacy page. Short, because there's little to disclose — and that
/// brevity is the selling point.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                row("No account", "There's nothing to sign up for.")
                row("No server", "CashLeak has no backend. Nothing you enter is sent anywhere.")
                row("No bank connection", "The app never asks for banking credentials and couldn't use them.")
                row("No analytics", "No tracking SDK, no crash reporter, no usage telemetry.")
                row("Your iCloud", "Sync uses your own private CloudKit database. Apple can't read it and neither can we.")
            }
            Section {
                Text("Receipt scanning runs on-device using Apple's Vision framework. Images never leave your phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
