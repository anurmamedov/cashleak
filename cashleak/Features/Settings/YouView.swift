import SwiftUI
import SwiftData

/// Profile: who you are, then everything grouped by what it's for, with the
/// account actions last.
///
/// Rebuilt to the proposed layout (D-025). Sign out used to sit directly under
/// your name; there was no way to delete the account, which App Review
/// requires of any app that lets you create one; card labels left over from
/// the one-automation-per-card assumption still invited people to add cards
/// that changed nothing; and Goals lived under Capture.
struct YouView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authentication: AuthenticationService

    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var goals: [Goal]
    @Query private var rules: [RecurringRule]
    @Query private var profiles: [UserProfile]

    @Query(sort: \CaptureLogEntry.receivedAt, order: .reverse)
    private var captures: [CaptureLogEntry]

    @State private var exportURL: URL?
    @State private var currency = AppSettings.currencyCode
    @State private var notificationTime = Date.now
    @State private var remindersEnabled = AppSettings.notificationsEnabled
    @State private var isUpdatingReminder = false
    @State private var showNotificationSettingsAlert = false

    @State private var isEditingProfile = false
    @State private var isDeletingAccount = false
    @State private var isConfirmingSignOut = false
    @State private var isEnablingFaceIDSignIn = false
    @State private var faceIDSignInOn = SavedSignIn.savedEmail != nil
    @State private var appLockOn = AppLock.isEnabled

    private let brand = Color(hex: "C65A2E")

    private var profile: UserProfile? { profiles.first }
    private var stats: AccountData.Stats { AccountData.stats(from: transactions) }
    private var supersededCount: Int { transactions.filter(\.isSuperseded).count }
    private var activeCount: Int { transactions.count - supersededCount }

    var body: some View {
        NavigationStack {
            List {
                profileCard
                    .scrollToTopAnchor()
                captureSection
                moneySection
                remindersSection
                securitySection
                dataSection
                helpSection
                // Debug tools sit above the account actions, so Sign out and
                // Delete account are always the last thing on the screen.
                #if DEBUG
                debugSection
                #endif
                accountSection
            }
            .listStyle(.insetGrouped)
            .scrollsToTopOnTabChange()
            .navigationTitle("Profile")
            .tint(brand)
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $isEditingProfile) {
                if let profile { EditProfileView(profile: profile) }
            }
            .sheet(isPresented: $isDeletingAccount) {
                DeleteAccountView()
            }
            .sheet(isPresented: $isEnablingFaceIDSignIn, onDismiss: refreshSecurity) {
                EnableFaceIDSignInView()
            }
            .alert("Notifications are off", isPresented: $showNotificationSettingsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow notifications for CashLeak in Settings to use the daily reminder.")
            }
            // An alert rather than a confirmation dialog: on iOS 26 a dialog
            // from a list floats as a bubble pointing at an unrelated row. An
            // alert is centred, with Cancel beside Sign out.
            .alert("Sign out of CashLeak?", isPresented: $isConfirmingSignOut) {
                Button("Cancel", role: .cancel) {}
                Button("Sign out", role: .destructive, action: signOut)
            } message: {
                Text("Your spending stays on this iPhone and in your iCloud. The app lock is turned off.")
            }
            .onAppear {
                loadNotificationTime()
                refreshSecurity()
            }
        }
    }

    // MARK: Rows

    /// A coloured tile, a title and an optional value — the same shape as every
    /// row on Overview and Analysis.
    private func row(
        _ title: String,
        icon: String,
        tint: Color,
        value: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(brand)
            .textCase(nil)
    }

    // MARK: Profile card

    private var profileCard: some View {
        Section {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    // Display only. The photo is changed in Edit, nowhere else.
                    ProfileAvatar(photo: profile?.photo, initials: profile?.initials ?? "", size: 56)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.headline)
                        if let email = profile?.email, !email.isEmpty {
                            Text(email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Button("Edit") { isEditingProfile = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(brand)
                        .buttonStyle(.borderless)
                        .disabled(profile == nil)
                }

                Divider()

                HStack(spacing: 0) {
                    stat("\(stats.sorted)", "sorted")
                    Divider().frame(height: 28)
                    stat(
                        stats.worthItShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        "worth it",
                        tint: Color(hex: "1D9E75")
                    )
                    Divider().frame(height: 28)
                    stat(
                        stats.since.map { $0.formatted(.dateTime.month(.abbreviated).year(.twoDigits)) } ?? "—",
                        "tracking since"
                    )
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
        }
    }

    private var displayName: String {
        guard let profile, !profile.fullName.isEmpty else { return "You" }
        return profile.fullName
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Capture

    private var walletStatus: CaptureStatus { .from(captures) }

    private var walletStatusText: String {
        switch walletStatus {
        case .notConnected: "Set up"
        case .missingMerchant: "Check step 5"
        case .working: "Working"
        case .quiet: "Check it"
        }
    }

    private var walletStatusTint: Color {
        switch walletStatus {
        case .notConnected: Color(hex: "854F0B")
        case .missingMerchant: Color(hex: "993C1D")
        case .working: Color(hex: "1D9E75")
        case .quiet: Color(hex: "C65A2E")
        }
    }

    private var captureSection: some View {
        Section {
            NavigationLink {
                WalletSetupView()
            } label: {
                row("Apple Pay capture", icon: "bolt.fill", tint: walletStatusTint, value: walletStatusText)
            }
            NavigationLink {
                CaptureLogView()
            } label: {
                row("Capture log", icon: "list.bullet.rectangle", tint: Color(hex: "888780"))
            }
            NavigationLink {
                RecurringRulesView()
            } label: {
                row("Recurring bills", icon: "repeat", tint: Color(hex: "7F77DD"), value: rules.isEmpty ? nil : "\(rules.count)")
            }
        } header: {
            header("Capture")
        }
    }

    // MARK: Money

    private var moneySection: some View {
        Section {
            NavigationLink {
                GoalsView()
            } label: {
                row("Goals", icon: "target", tint: brand, value: GoalStore.current(from: goals)?.name)
            }
            if let profile {
                NavigationLink {
                    TakeHomeView(profile: profile)
                } label: {
                    row(
                        "Monthly take-home",
                        icon: "wallet.pass",
                        tint: Color(hex: "639922"),
                        value: profile.monthlyTakeHome > 0 ? profile.monthlyTakeHome.currencyRounded : "Add"
                    )
                }
            }
            NavigationLink {
                CategoriesView()
            } label: {
                row("Categories", icon: "tag", tint: Color(hex: "D4537E"), value: "\(categories.count)")
            }
            Picker(selection: $currency) {
                ForEach(currencyOptions, id: \.self) { code in
                    Text(code).tag(code)
                }
            } label: {
                row("Currency", icon: "dollarsign", tint: Color(hex: "639922"))
            }
            .onChange(of: currency) { _, newValue in
                AppSettings.currencyCode = newValue
            }
        } header: {
            header("Money")
        }
    }

    private var currencyOptions: [String] {
        var options = AppSettings.offeredCurrencies
        if !options.contains(currency) { options.insert(currency, at: 0) }
        return options
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { remindersEnabled },
                set: { updateReminders(enabled: $0) }
            )) {
                row("Daily reminder", icon: "bell.fill", tint: Color(hex: "BA7517"))
            }
            .disabled(isUpdatingReminder)

            if remindersEnabled {
                DatePicker("Time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                    .padding(.leading, 42)
                    .onChange(of: notificationTime) { _, newValue in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        AppSettings.notificationHour = parts.hour ?? 21
                        AppSettings.notificationMinute = parts.minute ?? 0
                        Task { await DailyReminderScheduler.refresh(in: context) }
                    }
            }
        } header: {
            header("Reminders")
        } footer: {
            Text("Only when there's something waiting in Sort.")
        }
    }

    // MARK: Security

    private var securitySection: some View {
        Section {
            NavigationLink {
                LockSettingsView()
            } label: {
                row("App lock", icon: "faceid", tint: Color(hex: "378ADD"), value: appLockOn ? "On" : "Off")
            }

            // Only for email accounts — Sign in with Apple already uses Face ID.
            if !authentication.isAppleAccount && SavedSignIn.biometryIsAvailable {
                Toggle(isOn: Binding(
                    get: { faceIDSignInOn },
                    set: { wanted in
                        if wanted {
                            isEnablingFaceIDSignIn = true
                        } else {
                            SavedSignIn.forget()
                            faceIDSignInOn = false
                        }
                    }
                )) {
                    row("Sign in with Face ID", icon: "key.fill", tint: Color(hex: "378ADD"))
                }
            }
        } header: {
            header("Security")
        } footer: {
            Text("App lock asks for Face ID when you open CashLeak. Sign in with Face ID replaces typing your password after you sign out.")
        }
    }

    private func refreshSecurity() {
        faceIDSignInOn = SavedSignIn.savedEmail != nil
        appLockOn = AppLock.isEnabled
    }

    // MARK: Data and privacy

    private var dataSection: some View {
        Section {
            NavigationLink {
                HistoryView()
            } label: {
                row("History", icon: "clock.arrow.circlepath", tint: Color(hex: "888780"), value: "\(activeCount)")
            }
            Button(action: export) {
                row("Export CSV", icon: "square.and.arrow.up", tint: Color(hex: "888780"))
            }
            NavigationLink {
                PrivacyView()
            } label: {
                row("Privacy", icon: "lock.shield", tint: Color(hex: "888780"))
            }
            NavigationLink {
                DeleteOldPurchasesView()
            } label: {
                row("Delete old purchases", icon: "calendar.badge.minus", tint: Color(hex: "888780"))
            }
            if supersededCount > 0 {
                LabeledContent("Merged duplicates", value: "\(supersededCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            header("Data and privacy")
        }
    }

    // MARK: Help

    private var helpSection: some View {
        Section {
            Button(action: contactSupport) {
                row("Contact support", icon: "envelope.fill", tint: Color(hex: "888780"))
            }
            row("Version", icon: "info.circle", tint: Color(hex: "888780"), value: AppVersion.display)
        } header: {
            header("Help")
        }
    }

    /// The email arrives with the version already in it — the first thing
    /// support asks, and the thing people least know how to find.
    private func contactSupport() {
        let subject = "CashLeak support (\(AppVersion.display), iOS \(UIDevice.current.systemVersion))"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@karasandlabs.com"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let url = components.url { openURL(url) }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            Button {
                isConfirmingSignOut = true
            } label: {
                Text("Sign out")
                    .fontWeight(.semibold)
                    .foregroundStyle(brand)
                    .frame(maxWidth: .infinity)
            }
            // Full-width separator. Centred text otherwise starts the line
            // where the text starts, which reads as half a divider.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            Button(role: .destructive) {
                isDeletingAccount = true
            } label: {
                Text("Delete account")
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            Text("Your spending stays on this iPhone and in your own iCloud.")
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    /// Signing out also turns the app lock off — a lock on a signed-out app
    /// would only stand between the next person and the sign-in screen. The
    /// saved Face ID sign-in stays: that's what makes signing back in quick.
    private func signOut() {
        AppLock.removePassword()
        AppLock.disableDeviceAuthentication()
        try? authentication.signOut()
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
                simulateTap()
            }
            Button("Simulate 12 taps") {
                for _ in 0..<12 { simulateTap() }
            }
            Button("Clear transactions", role: .destructive) {
                SeedData.clearTransactions(in: context)
            }
        }
    }
    #endif

    // MARK: Actions

    #if DEBUG
    /// Merchant strings shaped like what card feeds actually deliver — processor
    /// prefixes, store numbers, city suffixes, and the occasional empty string
    /// from a timed-out trigger.
    ///
    /// **Invented, not collected.** That's exactly what L3 exists to fix. They're
    /// here so the capture log and normalizer can be exercised without a card;
    /// real strings replace them the moment the gate runs.
    private static let simulatedRawMerchants: [String?] = [
        "SQ *BLUE BOTTLE COFFEE",
        "BLUE BOTTLE #4412",
        "UBER   EATS",
        "TST* TERRONI",
        "LOBLAWS #1043 TORONTO ON",
        "SHELL C12345",
        "AMZN Mktp CA*MT4XY9",
        "PRESTO/METROLINX",
        "TIM HORTONS 4471",
        "NETFLIX.COM",
        "DOORDASH*ORDER",
        "CINEPLEX ODEON 2201 ON",
        nil,
    ]

    /// Goes through the same path a real tap does, including the capture log —
    /// otherwise the log stays empty and can't be checked without a terminal.
    private func simulateTap() {
        let raw = Self.simulatedRawMerchants.randomElement() ?? nil
        let amount = (Double.random(in: 3...90) * 100).rounded() / 100

        let result = TransactionIngest.ingest(
            amount: amount,
            merchant: raw,
            source: .applePay,
            into: context
        )

        CaptureLog.record(
            rawMerchant: raw,
            amount: amount,
            source: .applePay,
            outcome: {
                switch result {
                case .inserted: "inserted"
                case .duplicate: "duplicate"
                case .rejected(let reason): "rejected: \(reason.rawValue)"
                }
            }(),
            in: context
        )
    }
    #endif

    private func export() {
        exportURL = try? CSVExport.writeTemporaryFile(from: transactions)
    }

    private func loadNotificationTime() {
        var parts = DateComponents()
        parts.hour = AppSettings.notificationHour
        parts.minute = AppSettings.notificationMinute
        notificationTime = Calendar.current.date(from: parts) ?? .now
        remindersEnabled = AppSettings.notificationsEnabled
    }

    private func updateReminders(enabled: Bool) {
        if !enabled {
            remindersEnabled = false
            DailyReminderScheduler.disable()
            return
        }

        remindersEnabled = true
        isUpdatingReminder = true
        Task {
            let granted = await DailyReminderScheduler.enable(in: context)
            remindersEnabled = granted
            isUpdatingReminder = false
            if !granted { showNotificationSettingsAlert = true }
        }
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

/// Categories. Create, rename, recolour, reorder, delete.
///
/// The order here is the order of the chips on the Add screen, so the ones
/// used most can come first. Deleting always says what happens to the
/// purchases — they become uncategorised, never deleted (D-027).
struct CategoriesView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var editing: Category?
    @State private var isAdding = false
    @State private var pendingDelete: Category?

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button {
                        editing = category
                    } label: {
                        HStack(spacing: 12) {
                            CategoryTile(category: category)
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text("\(CategoryRules.purchaseCount(category))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            pendingDelete = category
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Tap Edit to drag them into the order the Add screen shows. The number is how many purchases each holds. Swipe left on a category to delete it.")
            }

            Section {
                Button {
                    isAdding = true
                } label: {
                    Label("Add a category", systemImage: "plus")
                        .foregroundStyle(Color(hex: "C65A2E"))
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .tint(Color(hex: "C65A2E"))
        .sheet(isPresented: $isAdding) { CategoryEditor(category: nil) }
        .sheet(item: $editing) { category in CategoryEditor(category: category) }
        .confirmCategoryDelete($pendingDelete) { category in
            CategoryRules.delete(category, in: context)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        try? context.save()
    }
}

/// A category's symbol on a pale wash of its colour — the same tile Overview
/// uses.
struct CategoryTile: View {
    let category: Category
    var size: CGFloat = 30

    var body: some View {
        let tint = Color(hex: category.colorHex)
        Image(systemName: category.icon)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    /// The one confirmation for deleting a category, used by the list's swipe
    /// and by the edit screen's button, so both say the same thing.
    func confirmCategoryDelete(
        _ pending: Binding<Category?>,
        perform: @escaping (Category) -> Void
    ) -> some View {
        confirmationDialog(
            "Delete \(pending.wrappedValue?.name ?? "category")?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { category in
            Button("Delete category", role: .destructive) { perform(category) }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            Text(CategoryRules.deleteMessage(for: category))
        }
    }
}

/// Create or edit a category.
struct CategoryEditor: View {

    let category: Category?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Category]

    @State private var name = ""
    @State private var icon = "circle"
    @State private var colorHex = "888780"
    @State private var kind: CategoryKind = .want
    @State private var pendingDelete: Category?

    private static let icons = [
        "circle", "cart", "fork.knife", "cup.and.saucer", "bag", "car",
        "tram", "fuelpump", "house", "bolt", "wifi", "phone", "shield",
        "cross.case", "heart", "pawprint", "figure.child", "book",
        "graduationcap", "gift", "tshirt", "scissors", "wrench", "ticket",
        "gamecontroller", "music.note", "airplane", "repeat", "creditcard",
    ]

    private static let colors = [
        "D85A30", "BA7517", "639922", "1D9E75", "378ADD",
        "7F77DD", "D4537E", "888780",
    ]

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private var isTaken: Bool {
        CategoryRules.isNameTaken(trimmed, among: existing, excluding: category)
    }

    private var canSave: Bool { !trimmed.isEmpty && !isTaken }

    /// A starter category whose name has changed — worth saying that automatic
    /// filing still lands here.
    private var renamedBuiltIn: String? {
        guard let category, !category.builtInName.isEmpty,
              trimmed.caseInsensitiveCompare(category.builtInName) != .orderedSame,
              !trimmed.isEmpty else { return nil }
        return category.builtInName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        Text("Want").tag(CategoryKind.want)
                        Text("Need").tag(CategoryKind.need)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if isTaken {
                        Label("You already have a \(trimmed) category.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color(hex: "A32D2D"))
                    } else if let original = renamedBuiltIn {
                        Label(
                            "Was \(original). Purchases that used to file there automatically still do.",
                            systemImage: "sparkles"
                        )
                    } else {
                        Text("Need or want is for grouping only. It never affects a verdict — whether something was worth it is always your call.")
                    }
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(Self.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                                        .padding(-3)
                                )
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.body)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(icon == symbol
                                              ? Color(hex: colorHex).opacity(0.22)
                                              : Color(.secondarySystemBackground))
                                )
                                .foregroundStyle(icon == symbol ? Color(hex: colorHex) : Color.secondary)
                                .onTapGesture { icon = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let category {
                    Section {
                        Button(role: .destructive) {
                            pendingDelete = category
                        } label: {
                            Text("Delete category")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color(hex: "C65A2E"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmCategoryDelete($pendingDelete) { category in
                CategoryRules.delete(category, in: context)
                dismiss()
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let category else { return }
        name = category.name
        icon = category.icon
        colorHex = category.colorHex
        kind = category.kind
    }

    private func save() {
        guard canSave else { return }

        if let category {
            category.name = trimmed
            category.icon = icon
            category.colorHex = colorHex
            category.kind = kind
        } else {
            let next = (existing.map(\.sortIndex).max() ?? -1) + 1
            context.insert(Category(
                name: trimmed, icon: icon, colorHex: colorHex,
                kind: kind, sortIndex: next
            ))
        }

        try? context.save()
        dismiss()
    }
}

/// What CashLeak keeps and where, in plain words — a summary of the privacy
/// policy, with a link to the full text (App Review 5.1.1 asks for the policy
/// to be reachable inside the app).
///
/// Worded carefully: it describes what the app does rather than promising
/// what can never happen, and it doesn't claim more than is true about
/// services CashLeak doesn't run — iCloud is Apple's (D-029).
struct PrivacyView: View {

    /// The full policy on the company website, not the source repository —
    /// so the repository can be private (D-033).
    static let policyURL = URL(string: "https://karasandlabs.com/cashleak/privacy")!

    var body: some View {
        List {
            Section {
                row("Your spending stays yours",
                    "Purchases, amounts, shops, verdicts and goals are stored on this iPhone and synced only through your own iCloud account. We don't receive them.")
                row("Your iCloud",
                    "Your data is kept in your private iCloud database, which we have no access to. Apple stores it encrypted; with Advanced Data Protection turned on in Settings, it's end-to-end encrypted.")
                row("Your account",
                    "Signing in uses your email address — or your Apple sign-in — and an account identifier. We don't store your name with your account; it stays in your profile.")
                row("Face ID sign-in",
                    "If you turn it on, your password is kept in this iPhone's Keychain, protected by Face ID. It isn't synced and is used only to sign you in.")
                row("Profile photo",
                    "Optional. It's resized on your iPhone and kept with the rest of your data, on the device and in your iCloud.")
                row("No bank connection",
                    "CashLeak doesn't ask for or use banking credentials.")
                row("No tracking or ads",
                    "CashLeak contains no analytics or advertising tools, and doesn't track you across apps or websites.")
            }

            Section {
                Link(destination: Self.policyURL) {
                    Label("Read the full privacy policy", systemImage: "doc.text")
                }
                Link(destination: URL(string: "mailto:support@karasandlabs.com")!) {
                    Label("Questions? support@karasandlabs.com", systemImage: "envelope")
                }
            } footer: {
                Text("CashLeak is published by Karasand Software Inc.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color(hex: "C65A2E"))
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
