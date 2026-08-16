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
    @Query private var goals: [Goal]
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
                GoalsView()
            } label: {
                Label("Goals · \(goals.count)", systemImage: "target")
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
            NavigationLink {
                HistoryView()
            } label: {
                HStack {
                    Label("History", systemImage: "list.bullet")
                    Spacer()
                    Text("\(activeCount)")
                        .foregroundStyle(.secondary)
                }
            }
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

/// Categories. Create, rename, recolour, delete.
///
/// Previously list-and-delete only — fourteen seeded categories, permanently,
/// and deleting one was irreversible. Anyone with a hobby, a pet or childcare
/// was stuck with someone else's taxonomy.
struct CategoriesView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var editing: Category?
    @State private var isAdding = false

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editing = category
                } label: {
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color(hex: category.colorHex))
                            .frame(width: 26)
                        Text(category.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(category.kind == .need ? "Need" : "Want")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)

            Section {
                Button {
                    isAdding = true
                } label: {
                    Label("Add a category", systemImage: "plus")
                }
            } footer: {
                Text("Deleting a category keeps its transactions — they become uncategorised.")
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAdding) { CategoryEditor(category: nil) }
        .sheet(item: $editing) { category in CategoryEditor(category: category) }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(categories[index])
        }
        try? context.save()
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
    @State private var budgetText = ""

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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
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
                    Text("Need or want is for grouping only. It never affects a verdict — whether something was worth it is always your call.")
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
                                .foregroundStyle(icon == symbol ? Color(hex: colorHex) : .secondary)
                                .onTapGesture { icon = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
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
        let trimmed = name.trimmingCharacters(in: .whitespaces)

        if let category {
            category.name = trimmed
            category.icon = icon
            category.colorHex = colorHex
            category.kind = kind
        } else {
            let next = (existing.map(\.sortIndex).max() ?? 0) + 1
            context.insert(Category(
                name: trimmed, icon: icon, colorHex: colorHex,
                kind: kind, sortIndex: next
            ))
        }

        try? context.save()
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
