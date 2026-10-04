import SwiftUI
import SwiftData
import PhotosUI

/// Number pad first. Amount → category → done.
///
/// Laid out in the same white cards on grouped grey as Overview (D-034), so it
/// reads as part of the app rather than a system form. The target is still
/// under five seconds without looking: store, date and verdict all have a
/// default that's right most of the time, and nothing is required but the
/// amount.
///
/// **Scan a receipt** fills the same sheet from a photo (D-036) — total,
/// store and date, each with a dot: green read clearly, orange worth a look.
/// The sheet *is* the check screen, so a scan is never saved without a person
/// seeing every field.
///
/// Everything saves through `TransactionIngest.ingest`, so a purchase Wallet
/// already caught merges instead of counting twice. A verdict chosen here
/// confirms the record — a person is looking straight at it. **Later** leaves
/// it unconfirmed, waiting in Sort like any capture.
struct AddTransactionSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    // Entry
    @State private var digits = ""
    @State private var merchant = ""
    @State private var note = ""
    @State private var suggestions: [String] = []
    @State private var selectedCategory: Category?
    @State private var categoryWasAutoFilled = false
    @State private var history: MerchantMemory.VerdictHistory?
    @State private var dayChoice: DayChoice = .today
    @State private var pickedDate = Date.now
    @State private var showingCalendar = false
    @State private var verdict: Verdict = .unrated
    @FocusState private var focusedField: EntryField?

    // Receipt
    @State private var source: TransactionSource = .manual
    @State private var receiptPhoto: UIImage?
    @State private var receiptData: Data?
    @State private var isReading = false
    @State private var scanMessage: String?
    @State private var amountCheck: ReceiptReading.Confidence?
    @State private var merchantCheck: ReceiptReading.Confidence?
    @State private var dateCheck: ReceiptReading.Confidence?
    @State private var scannedMerchant = ""
    @State private var showingCamera = false
    @State private var showingPhotos = false
    @State private var photoItem: PhotosPickerItem?

    /// CashLeak orange and the worth-it green, as on Overview.
    private let brand = Color(hex: "C65A2E")
    private let worthIt = Color(hex: "1D9E75")

    /// Seven digits is $99,999.99 — just under the ingest ceiling, so the pad
    /// can't produce an amount that would be rejected on save.
    private let maxDigits = 7

    private enum DayChoice { case today, yesterday, picked }
    private enum EntryField { case merchant, note }

    private var amount: Double { (Double(digits) ?? 0) / 100 }
    private var canSave: Bool { amount > 0 }

    private var date: Date {
        switch dayChoice {
        case .today: .now
        case .yesterday: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        case .picked: pickedDate
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 10) {
                        amountCard
                        categoryCard
                        dayCard
                        verdictCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)

                if focusedField == nil {
                    NumberPad(onDigit: append, onDelete: deleteLast)
                        .padding(.horizontal, 16)
                    saveButton
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCalendar) { calendarSheet }
            .fullScreenCover(isPresented: $showingCamera) {
                ReceiptCamera(
                    onFinish: { pages in
                        showingCamera = false
                        Task { await read(pages) }
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await read([image])
                    } else {
                        scanMessage = "That photo couldn't be opened. Try another."
                    }
                    photoItem = nil
                }
            }
        }
        .tint(brand)
        .presentationDetents([.large])
    }

    // MARK: Cards

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var amountCard: some View {
        card {
            VStack(spacing: 8) {
                if let receiptPhoto {
                    receiptBanner(receiptPhoto)
                }

                HStack(spacing: 8) {
                    Text(amount.currencyExact)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(canSave ? Color.primary : Color.secondary.opacity(0.5))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: digits)
                    if let amountCheck { ConfidenceDot(confidence: amountCheck) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)

                fieldBox(icon: "storefront", iconTint: brand) {
                    TextField("Where did you buy it?", text: $merchant)
                        .focused($focusedField, equals: .merchant)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .onChange(of: merchant) { _, newValue in
                            merchantChanged(to: newValue)
                        }
                    if let merchantCheck { ConfidenceDot(confidence: merchantCheck) }
                }

                if !suggestions.isEmpty {
                    suggestionRow
                }

                if categoryWasAutoFilled, let category = selectedCategory {
                    Text("\(category.name) · same as last time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                fieldBox(icon: "note.text", iconTint: .secondary) {
                    TextField("Note (optional)", text: $note)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                scanRow
            }
        }
    }

    private func fieldBox<Content: View>(
        icon: String,
        iconTint: Color,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconTint)
                .frame(width: 18)
            content()
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        merchant = suggestion
                        suggestions = []
                        focusedField = nil
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: Receipt

    @ViewBuilder
    private var scanRow: some View {
        if isReading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Reading the receipt…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        } else {
            VStack(spacing: 4) {
                if let scanMessage {
                    Text(scanMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                // A standard menu opens next to the link and covers nothing
                // that's being filled in — the system dialog sat over the
                // amount and store fields.
                Menu {
                    if ReceiptCamera.isAvailable {
                        Button {
                            startScan(.camera)
                        } label: {
                            Label("Take a photo", systemImage: "camera")
                        }
                    }
                    Button {
                        startScan(.photos)
                    } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label(
                        receiptPhoto == nil ? "Scan a receipt instead" : "Scan again",
                        systemImage: "doc.text.viewfinder"
                    )
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(brand)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    private func receiptBanner(_ photo: UIImage) -> some View {
        let needsCheck = [amountCheck, merchantCheck, dateCheck].contains { $0 == .check }
        return HStack(spacing: 10) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("From your receipt")
                    .font(.caption.weight(.semibold))
                Text(needsCheck ? "Orange dot: worth a second look" : "Everything read clearly")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: removeReceipt) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove receipt")
        }
    }

    private enum ScanSource { case camera, photos }

    private func startScan(_ source: ScanSource) {
        focusedField = nil
        scanMessage = nil
        switch source {
        case .camera: showingCamera = true
        case .photos: showingPhotos = true
        }
    }

    private func read(_ pages: [UIImage]) async {
        guard let first = pages.first else { return }
        isReading = true
        scanMessage = nil

        let lines = await ReceiptReader.lines(in: pages)
        let reading = ReceiptParser.parse(lines)
        isReading = false

        guard !reading.isEmpty else {
            scanMessage = "Couldn't read this receipt. Type it in, or try again flat and in good light."
            return
        }
        apply(reading, photo: first)
    }

    /// Fills the sheet from a reading. Anything the reading doesn't have is
    /// left as the person had it.
    private func apply(_ reading: ReceiptReading, photo: UIImage) {
        if let total = reading.total {
            digits = String(Int((total.value * 100).rounded()))
            amountCheck = total.confidence
        }

        if let found = reading.merchant {
            scannedMerchant = found.value
            merchant = found.value
            // A store the app already knows is as good as read clearly.
            let known = MerchantMemory.lastCategory(forMerchant: found.value, in: context) != nil
                || MerchantCategoryHints.categoryName(forMerchant: found.value) != nil
            merchantCheck = known ? .sure : found.confidence
            applyRememberedCategory(for: found.value)
            history = MerchantMemory.verdictHistory(forMerchant: found.value, in: context)
        }

        if selectedCategory == nil {
            let name = reading.merchant.flatMap { MerchantCategoryHints.categoryName(forMerchant: $0.value) }
                ?? reading.categoryHint
            if let name, let match = category(named: name) {
                selectedCategory = match
                categoryWasAutoFilled = false
            }
        }

        if let found = reading.date {
            let calendar = Calendar.current
            if calendar.isDateInToday(found.value) {
                dayChoice = .today
            } else if calendar.isDateInYesterday(found.value) {
                dayChoice = .yesterday
            } else {
                pickedDate = found.value
                dayChoice = .picked
            }
            dateCheck = found.confidence
        }

        receiptPhoto = photo
        receiptData = ReceiptReader.storedImage(from: photo)
        source = .scan
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Keeps whatever was filled in; only the photo and the dots go.
    private func removeReceipt() {
        receiptPhoto = nil
        receiptData = nil
        source = .manual
        amountCheck = nil
        merchantCheck = nil
        dateCheck = nil
        scannedMerchant = ""
    }

    private func category(named name: String) -> Category? {
        categories.first { $0.builtInName == name } ?? categories.first { $0.name == name }
    }

    // MARK: Category

    private var categoryCard: some View {
        card {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories) { category in
                        categoryChip(category)
                    }
                }
            }
        }
    }

    private func categoryChip(_ category: Category) -> some View {
        let isSelected = selectedCategory?.persistentModelID == category.persistentModelID
        let tint = Color(hex: category.colorHex)
        return Button {
            selectedCategory = isSelected ? nil : category
            categoryWasAutoFilled = false
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.name)
                    .font(.subheadline)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? tint.opacity(0.2) : Color(.tertiarySystemFill))
            .overlay(Capsule().stroke(isSelected ? tint : .clear, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Date

    /// Today and Yesterday cover nearly every late entry. Anything older —
    /// a receipt found in a coat pocket — goes through the calendar, and the
    /// chip then shows the date picked.
    private var dayCard: some View {
        card {
            HStack(spacing: 6) {
                dayChip("Today", isSelected: dayChoice == .today) {
                    dayChoice = .today
                    dateCheck = nil
                }
                dayChip("Yesterday", isSelected: dayChoice == .yesterday) {
                    dayChoice = .yesterday
                    dateCheck = nil
                }
                dayChip(
                    dayChoice == .picked ? pickedDate.formatted(.dateTime.month(.abbreviated).day()) : "Other day",
                    icon: "calendar",
                    isSelected: dayChoice == .picked
                ) {
                    showingCalendar = true
                }
                Spacer(minLength: 0)
                if let dateCheck { ConfidenceDot(confidence: dateCheck) }
            }
        }
    }

    private func dayChip(
        _ title: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.caption)
                }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? brand : Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var calendarSheet: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: $pickedDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)
            .navigationTitle("When was it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let calendar = Calendar.current
                        if calendar.isDateInToday(pickedDate) {
                            dayChoice = .today
                        } else if calendar.isDateInYesterday(pickedDate) {
                            dayChoice = .yesterday
                        } else {
                            dayChoice = .picked
                        }
                        dateCheck = nil
                        showingCalendar = false
                    }
                }
            }
        }
        .tint(brand)
        .presentationDetents([.medium, .large])
    }

    // MARK: Verdict

    /// Nothing is pre-selected but Later, whatever the history says (D-035).
    private var verdictCard: some View {
        card {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    verdictChip("Worth it", value: .worthIt, fill: worthIt)
                    verdictChip("Leak", value: .leak, fill: brand)
                    verdictChip("Later", value: .unrated, fill: nil)
                }
                if let history {
                    Text(history.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if verdict == .unrated {
                    Text("Later puts it in Sort to rate.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func verdictChip(_ title: String, value: Verdict, fill: Color?) -> some View {
        let isSelected = verdict == value
        return Button {
            verdict = value
        } label: {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected && fill != nil ? Color.white : Color.primary)
                .background {
                    if isSelected, let fill {
                        Capsule().fill(fill)
                    } else if isSelected {
                        Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    } else {
                        Capsule().fill(Color(.tertiarySystemFill))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(canSave ? "Add \(amount.currencyExact)" : "Add purchase")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(brand.opacity(canSave ? 1 : 0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: Memory

    private func merchantChanged(to newValue: String) {
        suggestions = MerchantMemory.recentMerchants(matching: newValue, in: context)
            .filter { $0.caseInsensitiveCompare(newValue) != .orderedSame }
        applyRememberedCategory(for: newValue)
        history = MerchantMemory.verdictHistory(forMerchant: newValue, in: context)
        if newValue != scannedMerchant { merchantCheck = nil }
    }

    /// Fills the category from the last time this merchant was filed — but
    /// only while the user hasn't chosen one themselves. An explicit tap always
    /// wins over memory.
    private func applyRememberedCategory(for merchantName: String) {
        guard selectedCategory == nil || categoryWasAutoFilled else { return }

        if let remembered = MerchantMemory.lastCategory(forMerchant: merchantName, in: context) {
            selectedCategory = remembered
            categoryWasAutoFilled = true
        } else if categoryWasAutoFilled {
            selectedCategory = nil
            categoryWasAutoFilled = false
        }
    }

    // MARK: Actions

    private func append(_ digit: String) {
        guard digits.count < maxDigits else { return }
        if digits.isEmpty && digit == "0" { return }
        digits.append(digit)
        amountCheck = nil
    }

    private func deleteLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
        amountCheck = nil
    }

    private func save() {
        guard canSave else { return }

        let result = TransactionIngest.ingest(
            amount: amount,
            merchant: merchant,
            date: date,
            source: source,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: selectedCategory,
            personVerdict: verdict == .unrated ? nil : verdict,
            receiptImage: receiptData,
            into: context
        )

        switch result {
        case .inserted, .duplicate:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        case .rejected:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Green: read clearly. Orange: worth a second look.
private struct ConfidenceDot: View {
    let confidence: ReceiptReading.Confidence

    var body: some View {
        Circle()
            .fill(confidence == .sure ? Color(hex: "1D9E75") : Color.orange)
            .frame(width: 8, height: 8)
            .accessibilityLabel(confidence == .sure ? "Read clearly" : "Check this")
    }
}

/// Large hit targets, no decimal key — digits accumulate from the right so
/// `450` reads as `$4.50`. One less thing to think about while paying.
private struct NumberPad: View {

    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
    ]

    private let keyHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key in
                        padButton(key) { onDigit(key) }
                    }
                }
            }
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: keyHeight)
                padButton("0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .frame(height: keyHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
        }
    }

    private func padButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .frame(height: keyHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
